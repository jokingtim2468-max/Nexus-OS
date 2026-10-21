#!/usr/bin/env python3
"""FreeForm — Vault: per-VM disk encryption with isolated keys.

Every VM workspace is a LUKS-encrypted disk (AES-256-XTS) with its OWN random
256-bit key. Each key is wrapped in its own keyfile under your master login, so
compromising one VM's key exposes ONLY that VM — never the others.

Key hierarchy:

    master login password  (you remember this; never stored)
            │  openssl PBKDF2-SHA256, 600k iters, random salt PER VM
            ▼
    wrapped key file   workspaces/<id>/vault/vmkey.enc      (one per VM)
            │  unwrap at launch -> ephemeral keyfile (chmod 600, deleted after)
            ▼
    VM disk key   (random 256-bit) ──► qcow2 LUKS AES-256-XTS on disk.qcow2

A CSV index (workspaces/vault-index.csv) records metadata only — no secrets.

We do NOT hand-roll crypto: openssl does the wrapping, LUKS/qemu does the disk.
Uses only the standard library + the openssl CLI.

  FREEFORM_MASTER=... python3 vault.py init kali      # make Kali's isolated key
  FREEFORM_MASTER=... python3 vault.py unlock kali --out /run/ff/kali.key
  python3 vault.py status                              # CSV index (no secrets)
  FREEFORM_MASTER=... python3 vault.py selftest        # prove round-trip
"""
from __future__ import annotations

import argparse
import csv
import getpass
import os
import secrets
import stat
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORKSPACES = os.path.join(ROOT, "workspaces")
INDEX = os.path.join(WORKSPACES, "vault-index.csv")

ITERS = 600000          # PBKDF2 rounds for the key wrap
CIPHER = "aes-256-cbc"  # wrap cipher (the DATA disk uses LUKS AES-256-XTS)


def vault_dir(vm: str) -> str:
    return os.path.join(WORKSPACES, vm, "vault")


def key_path(vm: str) -> str:
    return os.path.join(vault_dir(vm), "vmkey.enc")


DEVICE_KEY = os.path.expanduser(
    os.environ.get("FREEFORM_DEVICE_KEY", "~/.config/freeform/device.key"))


def get_master() -> str:
    m = os.environ.get("FREEFORM_MASTER")
    if not m:
        m = getpass.getpass("VM login password: ")
    return m


def device_key_hex(create: bool = False) -> str | None:
    """A random key bound to THIS machine (second factor).

    It stays on the device (ideally TPM-sealed). Combined with the password it
    unwraps the VM keys — so a stolen password + stolen disk, WITHOUT this file,
    cannot decrypt anything.
    """
    if os.path.exists(DEVICE_KEY):
        try:
            return open(DEVICE_KEY).read().strip()
        except OSError:
            return None
    if not create:
        return None
    os.makedirs(os.path.dirname(DEVICE_KEY), exist_ok=True)
    k = secrets.token_hex(32)
    with open(DEVICE_KEY, "w") as fh:
        fh.write(k)
    os.chmod(DEVICE_KEY, stat.S_IRUSR | stat.S_IWUSR)  # 600
    return k


def effective_secret(password: str, create_device: bool) -> str | None:
    """password + device key = the real unwrap secret (two-factor)."""
    dk = device_key_hex(create=create_device)
    if dk is None:
        return None
    return f"{password}\x1f{dk}"


def password_strength(pw: str) -> tuple[float, str]:
    """Rough entropy estimate (bits) + a verdict."""
    import math
    import re
    pool = 0
    if re.search(r"[a-z]", pw): pool += 26
    if re.search(r"[A-Z]", pw): pool += 26
    if re.search(r"\d", pw):     pool += 10
    if re.search(r"[^a-zA-Z0-9]", pw): pool += 32
    bits = len(pw) * math.log2(pool) if pool else 0.0
    verdict = ("very weak" if bits < 40 else "weak" if bits < 60
               else "ok" if bits < 80 else "strong")
    return bits, verdict


def _wrap(vmkey: bytes, master: str, out: str) -> bool:
    os.makedirs(os.path.dirname(out), exist_ok=True)
    env = os.environ.copy(); env["FF_M"] = master
    p = subprocess.run(
        ["openssl", "enc", "-" + CIPHER, "-salt", "-pbkdf2", "-iter", str(ITERS),
         "-md", "sha256", "-pass", "env:FF_M", "-out", out],
        input=vmkey, capture_output=True, env=env,
    )
    if p.returncode == 0:
        os.chmod(out, stat.S_IRUSR | stat.S_IWUSR)  # 600
    return p.returncode == 0


def _unwrap(enc_path: str, master: str) -> bytes | None:
    env = os.environ.copy(); env["FF_M"] = master
    p = subprocess.run(
        ["openssl", "enc", "-d", "-" + CIPHER, "-pbkdf2", "-iter", str(ITERS),
         "-md", "sha256", "-pass", "env:FF_M", "-in", enc_path],
        capture_output=True, env=env,
    )
    return p.stdout if p.returncode == 0 else None


def index_add(vm: str) -> None:
    os.makedirs(WORKSPACES, exist_ok=True)
    new = not os.path.exists(INDEX)
    rows = []
    if not new:
        with open(INDEX, newline="") as fh:
            rows = [r for r in csv.reader(fh)][1:] if os.path.getsize(INDEX) else []
        rows = [r for r in rows if r and r[0] != vm]
    rows.append([vm, "luks/aes-256-xts", f"pbkdf2-sha256/{ITERS}",
                 "vault/vmkey.enc", time.strftime("%Y-%m-%d")])
    with open(INDEX, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["vm_id", "disk_cipher", "key_kdf", "keyfile", "created"])
        w.writerows(rows)


def cmd_init(vm: str, force: bool = False) -> int:
    if os.path.exists(key_path(vm)):
        print(f"vault already exists for '{vm}' (use rotate to replace).")
        return 1
    master = get_master()
    bits, verdict = password_strength(master)
    print(f"password strength: ~{bits:.0f} bits ({verdict})")
    if bits < 60 and not force:
        print("REJECTED: password is too weak. Use a longer passphrase "
              "(try `python3 vault.py genpass`), or pass --force to override.",
              file=sys.stderr)
        return 2
    sec = effective_secret(master, create_device=True)   # binds to THIS device
    if sec is None:
        print("error: could not create/read the device key.", file=sys.stderr)
        return 2
    vmkey = secrets.token_hex(32).encode()   # 256-bit, 64 random hex chars
    if not _wrap(vmkey, sec, key_path(vm)):
        print("error: openssl wrap failed.", file=sys.stderr)
        return 2
    index_add(vm)
    print(f"Encrypted key created for '{vm}':")
    print(f"  wrapped key : {key_path(vm)}  (600, random 256-bit, isolated)")
    print(f"  index       : {INDEX}")
    print(f"  device key  : {DEVICE_KEY}  (second factor — stays on this machine)")
    print("Unwrapping needs BOTH your password AND this machine's device key, so "
          "a stolen password + disk can't decrypt the raw files elsewhere. Your "
          "password is never stored; the device key never leaves this machine.")
    return 0


def cmd_unlock(vm: str, out: str | None) -> int:
    if not os.path.exists(key_path(vm)):
        print(f"no vault for '{vm}' — run init first.", file=sys.stderr)
        return 2
    sec = effective_secret(get_master(), create_device=False)
    if sec is None:
        print(f"error: device key missing ({DEVICE_KEY}). These files can only be "
              f"unlocked on the machine that created them — a stolen password + "
              f"disk can't decrypt without it.", file=sys.stderr)
        return 2
    vmkey = _unwrap(key_path(vm), sec)
    if vmkey is None:
        print("error: wrong password or corrupt keyfile.", file=sys.stderr)
        return 2
    if out:
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "wb") as fh:
            fh.write(vmkey)
        os.chmod(out, stat.S_IRUSR | stat.S_IWUSR)
        print(f"VM key written to ephemeral file: {out} (600). "
              f"Pass it to qemu as a LUKS secret, then delete it.")
    else:
        sys.stdout.buffer.write(vmkey)
    return 0


def _secure_erase(path: str, passes: int = 3) -> bool:
    """Overwrite a (small) file with random bytes, then unlink it.

    Good for the key file on spinning disks and tmpfs. On SSDs, wear-leveling
    may leave remnants — but the key is still ciphertext (wrapped under your
    master), so a remnant is useless without your master password too.
    """
    if not os.path.exists(path):
        return False
    try:
        size = os.path.getsize(path)
        with open(path, "r+b", buffering=0) as f:
            for _ in range(passes):
                f.seek(0)
                f.write(os.urandom(max(size, 1)))
                f.flush()
                os.fsync(f.fileno())
        os.remove(path)
        return True
    except OSError:
        return False


def _index_remove(vm: str) -> None:
    if not os.path.exists(INDEX):
        return
    with open(INDEX, newline="") as fh:
        rows = list(csv.reader(fh))
    header, data = (rows[0], rows[1:]) if rows else (None, [])
    data = [r for r in data if r and r[0] != vm]
    with open(INDEX, "w", newline="") as fh:
        w = csv.writer(fh)
        if header:
            w.writerow(header)
        w.writerows(data)


def cmd_shred(vm: str, confirm: bool, rm_disk: bool) -> int:
    """Crypto-shred: destroy the VM's key so its encrypted disk is unrecoverable.

    We never wipe the multi-GB disk. We securely erase the tiny wrapped key; the
    256-bit disk key becomes unrecoverable, so the ciphertext is permanent noise.
    """
    kp = key_path(vm)
    disk = ws_disk_path(vm)
    have_key = os.path.exists(kp)
    have_disk = os.path.exists(disk)
    if not have_key and not have_disk:
        print(f"nothing to shred for '{vm}'.")
        return 1

    print(f"Crypto-shred '{vm}':")
    print(f"  1. securely erase the wrapped key  {kp}  ({'present' if have_key else 'missing'})")
    print(f"     → the 256-bit disk key becomes unrecoverable")
    print(f"  2. remove its vault dir + CSV index row")
    if have_disk:
        print(f"  3. disk {disk} is now cryptographic noise — "
              + ("delete it now" if rm_disk else "safe to delete/trash anytime"))
    if not confirm:
        print("\n(plan only — add --confirm. THIS IS IRREVERSIBLE: the data can "
              "never be decrypted again.)")
        return 0

    ok = _secure_erase(kp, passes=3) if have_key else True
    # remove any ephemeral unlocked copies and the vault dir
    vd = vault_dir(vm)
    if os.path.isdir(vd):
        for f in os.listdir(vd):
            _secure_erase(os.path.join(vd, f), passes=1)
        try:
            os.rmdir(vd)
        except OSError:
            pass
    _index_remove(vm)
    if rm_disk and have_disk:
        try:
            os.remove(disk)  # plain delete is fine — it's already undecryptable
            print(f"  removed {disk}")
        except OSError:
            pass
    print(f"\nDone. '{vm}' key destroyed{' and disk removed' if rm_disk else ''}. "
          f"The data is now permanently unrecoverable.")
    return 0 if ok or not have_key else 1


def ws_disk_path(vm: str) -> str:
    return os.path.join(WORKSPACES, vm, "disk.qcow2")


def cmd_genpass() -> int:
    pw = secrets.token_urlsafe(16)   # ~22 chars, ~128 bits of entropy
    bits, verdict = password_strength(pw)
    print(pw)
    print(f"(~{bits:.0f} bits, {verdict} — store it in a password manager; it is "
          f"NOT recoverable if lost)", file=sys.stderr)
    return 0


def cmd_status() -> int:
    if not os.path.exists(INDEX):
        print("No vaults yet. Run: vault.py init <distro>")
        return 0
    print("FreeForm Vault — encrypted VM keys (metadata only, no secrets)")
    print("=" * 60)
    with open(INDEX, newline="") as fh:
        for i, row in enumerate(csv.reader(fh)):
            print("  " + "  ".join(f"{c:<20}" if i == 0 else f"{c:<20}" for c in row))
    return 0


def cmd_selftest() -> int:
    """Prove wrap->unwrap round-trips, without printing any key."""
    import tempfile
    master = "throwaway-" + secrets.token_hex(8)
    vmkey = secrets.token_hex(32).encode()
    with tempfile.TemporaryDirectory() as d:
        enc = os.path.join(d, "k.enc")
        if not _wrap(vmkey, master, enc):
            print("FAIL: wrap")
            return 1
        back = _unwrap(enc, master)
        ok = back == vmkey
        wrong = _unwrap(enc, master + "x")  # wrong password must fail
        print(f"wrap/unwrap round-trip : {'OK' if ok else 'FAIL'}")
        print(f"wrong-password rejected : {'OK' if not wrong else 'FAIL'}")
        print(f"key length              : {len(vmkey)} hex chars (256-bit)")
        return 0 if ok and not wrong else 1


def qemu_luks_hint(vm: str) -> None:
    key = f"/run/freeform/{vm}.key"
    print("\nUse with qemu (after `unlock --out {0}`):".format(key))
    print(f"  qemu-img create -f qcow2 --object secret,id=s0,file={key} \\")
    print(f"    -o encrypt.format=luks,encrypt.key-secret=s0 \\")
    print(f"    workspaces/{vm}/disk.qcow2 40G")
    print(f"  # launch: -object secret,id=s0,file={key} "
          f"-drive file=...,encrypt.key-secret=s0  ; then shred {key}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="FreeForm Vault — per-VM encryption")
    sub = ap.add_subparsers(dest="action")
    i = sub.add_parser("init"); i.add_argument("vm"); i.add_argument("--force", action="store_true", help="allow a weak password")
    u = sub.add_parser("unlock"); u.add_argument("vm"); u.add_argument("--out", default=None)
    sub.add_parser("status")
    sub.add_parser("selftest")
    sub.add_parser("genpass")
    s = sub.add_parser("shred", help="crypto-erase a VM by destroying its key")
    s.add_argument("vm"); s.add_argument("--confirm", action="store_true")
    s.add_argument("--rm-disk", action="store_true", help="also delete the (now useless) disk")
    h = sub.add_parser("qemu-hint"); h.add_argument("vm")
    args = ap.parse_args(argv)

    if args.action == "init":
        rc = cmd_init(args.vm, args.force)
        if rc == 0:
            qemu_luks_hint(args.vm)
        return rc
    if args.action == "genpass":
        return cmd_genpass()
    if args.action == "unlock":
        return cmd_unlock(args.vm, args.out)
    if args.action == "selftest":
        return cmd_selftest()
    if args.action == "shred":
        return cmd_shred(args.vm, args.confirm, args.rm_disk)
    if args.action == "qemu-hint":
        qemu_luks_hint(args.vm); return 0
    return cmd_status()


if __name__ == "__main__":
    raise SystemExit(main())
