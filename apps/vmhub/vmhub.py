#!/usr/bin/env python3
"""FreeForm — VM Hub.

FreeForm is a hub that launches each Linux distro (Kali, Ubuntu, ...) in its own
VM with a persistent **workspace** (saved disk), and every guest runs the real
MacShell (Hyprland + Quickshell) so they all share the same Mac look.

This manager:
  - keeps one workspace per distro under  workspaces/<id>/  (persistent qcow2),
  - builds the QEMU command to boot it (with 3D accel for MacShell's Liquid
    Glass GLSL shader),
  - provisions MacShell into a guest.

Safe by default: prints what it would do. Pass --run to actually execute (needs
qemu + KVM). Pure standard library.

  python3 vmhub.py list                 # distros + workspace status
  python3 vmhub.py create kali          # make Kali's workspace disk
  python3 vmhub.py launch kali --iso kali.iso   # show the QEMU command
  python3 vmhub.py launch kali --iso kali.iso --run   # actually boot it
  python3 vmhub.py provision kali       # how to install MacShell in the guest
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DISTRO_DIR = os.path.join(ROOT, "distros")
WORKSPACES = os.path.join(ROOT, "workspaces")


def load_registry() -> dict:
    try:
        with open(os.path.join(DISTRO_DIR, "registry.json")) as fh:
            return {k: v for k, v in json.load(fh).items() if not k.startswith("_")}
    except (OSError, ValueError):
        return {}


def all_distros() -> list[dict]:
    reg = load_registry()
    return reg.get("recommended", []) + reg.get("custom", [])


def find_distro(distro_id: str) -> dict | None:
    for d in all_distros():
        if d.get("id") == distro_id:
            return d
    return None


def ws_dir(distro_id: str) -> str:
    return os.path.join(WORKSPACES, distro_id)


def ws_disk(distro_id: str) -> str:
    return os.path.join(ws_dir(distro_id), "disk.qcow2")


def ws_meta(distro_id: str) -> str:
    return os.path.join(ws_dir(distro_id), "meta.json")


def have(cmd: str) -> bool:
    from shutil import which
    return which(cmd) is not None


# --------------------------------------------------------------------------- #
def cmd_list() -> int:
    print("FreeForm VM Hub — distros & workspaces")
    print("=" * 52)
    for d in all_distros():
        did = d["id"]
        disk = ws_disk(did)
        if os.path.exists(disk):
            size = os.path.getsize(disk) / (1024**3)
            state = f"workspace: {size:.1f} GiB saved"
        else:
            state = "workspace: none yet (run `create`)"
        print(f"  {d['name']:<14} [{did:<7}] {state}")
    print(f"\nqemu: {'found' if have('qemu-system-x86_64') else 'MISSING (needed to run)'}")
    return 0


def cmd_create(distro_id: str, size: str, run: bool, keyfile: str | None = None) -> int:
    d = find_distro(distro_id)
    if not d:
        print(f"error: unknown distro '{distro_id}'", file=sys.stderr)
        return 2
    os.makedirs(ws_dir(distro_id), exist_ok=True)
    disk = ws_disk(distro_id)
    if os.path.exists(disk):
        print(f"workspace already exists: {disk}")
        return 0
    # metadata is a safe small write; the big disk is created by qemu-img
    meta = {"id": distro_id, "name": d["name"], "created": time.strftime("%Y-%m-%d"),
            "disk": "disk.qcow2", "size": size, "shell": "MacShell (Hyprland/Quickshell)",
            "encrypted": bool(keyfile)}
    with open(ws_meta(distro_id), "w") as fh:
        json.dump(meta, fh, indent=2)
    if keyfile:
        # LUKS-encrypted disk using this VM's isolated key (from vault.py unlock)
        qemu_img = ["qemu-img", "create", "-f", "qcow2",
                    "--object", f"secret,id=s0,file={keyfile}",
                    "-o", "encrypt.format=luks,encrypt.key-secret=s0", disk, size]
    else:
        qemu_img = ["qemu-img", "create", "-f", "qcow2", disk, size]
    print(("RUN  " if run else "PLAN ") + " ".join(qemu_img))
    if run:
        if not have("qemu-img"):
            print("error: qemu-img not installed.", file=sys.stderr)
            return 2
        return subprocess.call(qemu_img)
    print(f"\nWorkspace metadata written: {ws_meta(distro_id)}")
    print("(disk not created — re-run with --run once qemu-img is available)")
    return 0


def build_qemu(distro_id: str, iso: str | None, mem: int, cpus: int, keyfile: str | None = None) -> list[str]:
    disk = ws_disk(distro_id)
    drive = f"file={disk},if=virtio,format=qcow2"
    secret = []
    if keyfile:
        # the disk is LUKS-encrypted (vault.py); unlock the per-VM key first
        secret = ["-object", f"secret,id=s0,file={keyfile}"]
        drive += ",encrypt.key-secret=s0"
    cmd = [
        "qemu-system-x86_64",
        "-enable-kvm", "-cpu", "host",
        "-m", str(mem), "-smp", str(cpus),
        *secret,
        "-drive", drive,
        # 3D-accelerated virtio GPU so MacShell's Liquid Glass GLSL shader runs
        "-device", "virtio-vga-gl", "-display", "gtk,gl=on",
        "-device", "virtio-net,netdev=n0", "-netdev", "user,id=n0",
        "-usb", "-device", "usb-tablet",
        "-name", f"FreeForm: {distro_id}",
    ]
    if iso:
        cmd += ["-cdrom", iso, "-boot", "menu=on"]
    return cmd


def cmd_launch(distro_id: str, iso: str | None, mem: int, cpus: int, run: bool, keyfile: str | None = None) -> int:
    d = find_distro(distro_id)
    if not d:
        print(f"error: unknown distro '{distro_id}'", file=sys.stderr)
        return 2
    if not os.path.exists(ws_disk(distro_id)):
        print(f"no workspace yet — run:  python3 vmhub.py create {distro_id} --run")
        return 1
    cmd = build_qemu(distro_id, iso, mem, cpus, keyfile)
    print(f"Launching {d['name']} VM (workspace: {ws_disk(distro_id)})")
    print(("RUN  " if run else "PLAN ") + " ".join(cmd))
    if run:
        if not have("qemu-system-x86_64"):
            print("error: qemu-system-x86_64 not installed.", file=sys.stderr)
            return 2
        # record last launch
        try:
            meta = json.load(open(ws_meta(distro_id)))
            meta["last_launch"] = time.strftime("%Y-%m-%d %H:%M")
            json.dump(meta, open(ws_meta(distro_id), "w"), indent=2)
        except (OSError, ValueError):
            pass
        return subprocess.call(cmd)
    print("\n(plan only — add --run to boot it. First boot installs from the ISO "
          "into the workspace; later boots resume the saved workspace.)")
    return 0


def cmd_provision(distro_id: str) -> int:
    print(f"Provision MacShell into the {distro_id} guest")
    print("=" * 52)
    print("Run these INSIDE the running VM (one-time):")
    print("""
  # 1. Hyprland + Quickshell + shader tools (names vary per distro)
  #    Arch:   pacman -S hyprland qt6-shadertools pipewire ...
  #    Ubuntu/Kali/Debian: build Quickshell 0.3+ and install Hyprland 0.55+
  # 2. Clone and install MacShell (bundled at vendor/MacShell):
  git clone https://github.com/0-ss/MacShell
  cd MacShell && ./install.sh
  # 3. Use the provided hyprland.lua / hypr-macshell config so MacShell loads.
""")
    print("FreeForm ships MacShell at vendor/MacShell (MIT). The conversion kit "
          "(apps/conversion-kit) installs the drivers/deps; this step adds the shell.")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="FreeForm VM Hub")
    sub = ap.add_subparsers(dest="action")
    sub.add_parser("list")
    c = sub.add_parser("create"); c.add_argument("distro"); c.add_argument("--size", default="40G"); c.add_argument("--run", action="store_true"); c.add_argument("--key", default=None, help="LUKS keyfile from `vault.py unlock` (encrypted disk)")
    l = sub.add_parser("launch"); l.add_argument("distro"); l.add_argument("--iso", default=None); l.add_argument("--mem", type=int, default=4096); l.add_argument("--cpus", type=int, default=4); l.add_argument("--run", action="store_true"); l.add_argument("--key", default=None, help="LUKS keyfile from `vault.py unlock`")
    p = sub.add_parser("provision"); p.add_argument("distro")
    args = ap.parse_args(argv)

    if args.action == "create":
        return cmd_create(args.distro, args.size, args.run, args.key)
    if args.action == "launch":
        return cmd_launch(args.distro, args.iso, args.mem, args.cpus, args.run, args.key)
    if args.action == "provision":
        return cmd_provision(args.distro)
    return cmd_list()


if __name__ == "__main__":
    raise SystemExit(main())
