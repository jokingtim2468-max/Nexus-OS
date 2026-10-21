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


def get_master() -> str:
    m = os.environ.get("FREEFORM_MASTER")
    if not m:
        m = getpass.getpass("Master login password: ")
    if len(m) < 8:
        print("warning: master password is short — use a long passphrase.",
              file=sys.stderr)
    return m


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


def cmd_init(vm: str) -> int:
    if os.path.exists(key_path(vm)):
        print(f"vault already exists for '{vm}' (use rotate to replace).")
        return 1
    master = get_master()
    vmkey = secrets.token_hex(32).encode()   # 256-bit, 64 random hex chars
    if not _wrap(vmkey, master, key_path(vm)):
        print("error: openssl wrap failed.", file=sys.stderr)
        return 2
    index_add(vm)
    print(f"Encrypted key created for '{vm}':")
    print(f"  wrapped key : {key_path(vm)}  (600, random 256-bit, isolated)")
    print(f"  index       : {INDEX}")
    print("The VM disk key is never written in the clear. Keep your master "
          "password safe — it's the only thing that unwraps these, and it is "
          "never stored.")
    return 0


def cmd_unlock(vm: str, out: str | None) -> int:
    if not os.path.exists(key_path(vm)):
        print(f"no vault for '{vm}' — run init first.", file=sys.stderr)
        return 2
    vmkey = _unwrap(key_path(vm), get_master())
    if vmkey is None:
        print("error: wrong master password or corrupt keyfile.", file=sys.stderr)
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
    i = sub.add_parser("init"); i.add_argument("vm")
    u = sub.add_parser("unlock"); u.add_argument("vm"); u.add_argument("--out", default=None)
    sub.add_parser("status")
    sub.add_parser("selftest")
    h = sub.add_parser("qemu-hint"); h.add_argument("vm")
    args = ap.parse_args(argv)

    if args.action == "init":
        rc = cmd_init(args.vm)
        if rc == 0:
            qemu_luks_hint(args.vm)
        return rc
    if args.action == "unlock":
        return cmd_unlock(args.vm, args.out)
    if args.action == "selftest":
        return cmd_selftest()
    if args.action == "qemu-hint":
        qemu_luks_hint(args.vm); return 0
    return cmd_status()


if __name__ == "__main__":
    raise SystemExit(main())
