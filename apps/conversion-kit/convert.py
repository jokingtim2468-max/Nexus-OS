#!/usr/bin/env python3
"""Freeform — Linux Conversion Kit.

Turns a plain Linux install into a machine that runs apps from other OSes, by
installing (1) as much driver/firmware coverage as it can and (2) the
compatibility layers that run foreign apps without a VM:

  Windows apps  -> Wine + Proton (syscall translation, close to native)
  Android apps  -> Waydroid (containerized Android)
  macOS apps    -> Darling (partial; experimental)
  Linux apps    -> Flatpak / Flathub

Safe by default: prints a PLAN and changes nothing. Pass --install to apply
(needs root; it asks first). Pure standard library.

Usage:
  python3 convert.py                 # detect + print the plan (no changes)
  python3 convert.py --only drivers  # just the driver/firmware plan
  python3 convert.py --json          # machine-readable plan (for the UI)
  sudo python3 convert.py --install  # actually install (asks to confirm)
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys

# --------------------------------------------------------------------------- #
# Detection                                                                    #
# --------------------------------------------------------------------------- #
PKG_MANAGERS = ["apt-get", "dnf", "pacman", "zypper", "apk"]

GPU_VENDOR = {
    "0x8086": "intel",
    "0x10de": "nvidia",
    "0x1002": "amd",
    "0x1af4": "virtio",   # paravirtual (VM)
}


def detect_distro() -> dict:
    info = {"name": "Linux", "id": "", "version": ""}
    try:
        with open("/etc/os-release") as fh:
            kv = dict(
                line.rstrip().split("=", 1)
                for line in fh if "=" in line
            )
        info["name"] = kv.get("NAME", "Linux").strip('"')
        info["id"] = kv.get("ID", "").strip('"')
        info["version"] = kv.get("VERSION_ID", "").strip('"')
    except OSError:
        pass
    return info


def detect_pkg_manager() -> str | None:
    for pm in PKG_MANAGERS:
        if shutil.which(pm):
            return pm
    return None


def detect_gpus() -> list[dict]:
    gpus = []
    base = "/sys/bus/pci/devices"
    if not os.path.isdir(base):
        return gpus
    for entry in sorted(os.listdir(base)):
        dev = os.path.join(base, entry)
        try:
            with open(os.path.join(dev, "class")) as fh:
                cls = fh.read().strip()
        except OSError:
            continue
        if not cls.startswith("0x03"):  # 0x03 = display controller
            continue
        vid = _read(os.path.join(dev, "vendor"))
        drv = None
        link = os.path.join(dev, "driver")
        if os.path.islink(link):
            drv = os.path.basename(os.readlink(link))
        gpus.append({
            "slot": entry,
            "vendor_id": vid,
            "vendor": GPU_VENDOR.get(vid, "unknown"),
            "driver": drv,
        })
    return gpus


def detect_layers() -> dict:
    return {t: bool(shutil.which(t)) for t in
            ("wine", "winetricks", "proton", "waydroid", "flatpak", "darling", "steam", "lutris")}


def _read(p: str) -> str | None:
    try:
        with open(p) as fh:
            return fh.read().strip()
    except OSError:
        return None


# --------------------------------------------------------------------------- #
# Package maps (per package manager)                                           #
# --------------------------------------------------------------------------- #
# Each entry: logical name -> {pm: [packages]}. Missing pm => "not mapped yet".
DRIVER_PKGS = {
    "firmware":      {"apt-get": ["linux-firmware"], "dnf": ["linux-firmware"], "pacman": ["linux-firmware"]},
    "intel-microcode": {"apt-get": ["intel-microcode"], "dnf": ["microcode_ctl"], "pacman": ["intel-ucode"]},
    "amd-microcode": {"apt-get": ["amd64-microcode"], "dnf": ["linux-firmware"], "pacman": ["amd-ucode"]},
    "mesa (GPU)":    {"apt-get": ["mesa-vulkan-drivers", "libgl1-mesa-dri"], "dnf": ["mesa-vulkan-drivers"], "pacman": ["mesa", "vulkan-icd-loader"]},
    "nvidia":        {"apt-get": ["nvidia-driver-550"], "dnf": ["akmod-nvidia"], "pacman": ["nvidia", "nvidia-utils"]},
    "amd (extra)":   {"apt-get": ["firmware-amd-graphics"], "dnf": ["xorg-x11-drv-amdgpu"], "pacman": ["xf86-video-amdgpu"]},
    "printers/scanners": {"apt-get": ["printer-driver-all", "sane-utils"], "dnf": ["hplip", "sane-backends"], "pacman": ["cups", "sane"]},
    "bluetooth/wifi fw": {"apt-get": ["bluez", "wireless-regdb"], "dnf": ["bluez"], "pacman": ["bluez", "wireless-regdb"]},
}

LAYER_PKGS = {
    "Windows: Wine":     {"apt-get": ["wine", "winetricks"], "dnf": ["wine", "winetricks"], "pacman": ["wine", "winetricks"]},
    "Windows: Lutris":   {"apt-get": ["lutris"], "dnf": ["lutris"], "pacman": ["lutris"]},
    "Windows: Steam/Proton": {"apt-get": ["steam"], "dnf": ["steam"], "pacman": ["steam"]},
    "Android: Waydroid": {"apt-get": ["waydroid"], "dnf": ["waydroid"], "pacman": ["waydroid"]},
    "Linux: Flatpak":    {"apt-get": ["flatpak"], "dnf": ["flatpak"], "pacman": ["flatpak"]},
}

# Things with no clean package — documented, not auto-installed.
MANUAL_NOTES = {
    "macOS: Darling": "Usually built from source or a distro-specific build; "
                      "partial coverage (mostly CLI). Experimental — see docs/COMPATIBILITY.md.",
    "Windows: Proton-GE": "Install via ProtonUp-Qt or protonup after Steam; "
                          "newer than bundled Proton.",
}

INSTALL_CMD = {
    "apt-get": ["apt-get", "install", "-y"],
    "dnf":     ["dnf", "install", "-y"],
    "pacman":  ["pacman", "-S", "--noconfirm"],
    "zypper":  ["zypper", "install", "-y"],
    "apk":     ["apk", "add"],
}


# --------------------------------------------------------------------------- #
# Plan building                                                                #
# --------------------------------------------------------------------------- #
def build_plan(pm: str | None, gpus: list[dict], only: str | None) -> dict:
    drivers: list[dict] = []
    if only in (None, "drivers"):
        want = ["firmware", "printers/scanners", "bluetooth/wifi fw", "mesa (GPU)"]
        vendors = {g["vendor"] for g in gpus}
        if "intel" in vendors or not gpus:
            want.insert(1, "intel-microcode")
        if "amd" in vendors:
            want += ["amd-microcode", "amd (extra)"]
        if "nvidia" in vendors:
            want.append("nvidia")
        for name in want:
            pkgs = DRIVER_PKGS.get(name, {}).get(pm, []) if pm else []
            drivers.append({"name": name, "packages": pkgs,
                            "mapped": bool(pkgs)})

    layers: list[dict] = []
    if only in (None, "layers", "apps"):
        for name, m in LAYER_PKGS.items():
            pkgs = m.get(pm, []) if pm else []
            layers.append({"name": name, "packages": pkgs, "mapped": bool(pkgs)})

    manual = [{"name": k, "note": v} for k, v in MANUAL_NOTES.items()] \
        if only in (None, "layers", "apps") else []

    return {"drivers": drivers, "layers": layers, "manual": manual}


def all_packages(plan: dict) -> list[str]:
    pkgs: list[str] = []
    for group in ("drivers", "layers"):
        for item in plan[group]:
            pkgs += item["packages"]
    # dedupe, keep order
    seen = set()
    return [p for p in pkgs if not (p in seen or seen.add(p))]


def coverage(layers_present: dict, plan: dict) -> dict:
    planned = {i["name"] for i in plan["layers"] if i["mapped"]}
    return {
        "Windows apps": layers_present["wine"] or "Windows: Wine" in planned,
        "Android apps": layers_present["waydroid"] or "Android: Waydroid" in planned,
        "Linux (Flatpak)": layers_present["flatpak"] or "Linux: Flatpak" in planned,
        "macOS apps": layers_present["darling"],  # manual only
    }


# --------------------------------------------------------------------------- #
# Output                                                                        #
# --------------------------------------------------------------------------- #
def print_plan(ctx: dict) -> None:
    d, pm, gpus, plan = ctx["distro"], ctx["pm"], ctx["gpus"], ctx["plan"]
    print("Freeform — Linux Conversion Kit")
    print("=" * 60)
    print(f"Distro : {d['name']} {d['version']}  (id={d['id'] or '?'})")
    print(f"Package manager : {pm or 'UNKNOWN — cannot map packages'}")
    if gpus:
        for g in gpus:
            print(f"GPU : {g['slot']}  {g['vendor']} ({g['vendor_id']})  "
                  f"driver={g['driver'] or 'none'}")
    else:
        print("GPU : none detected (headless / VM)")
    print()

    def section(title, items):
        print(f"[{title}]")
        for it in items:
            if it.get("packages") is not None:
                if it["mapped"]:
                    print(f"  + {it['name']:<22} {' '.join(it['packages'])}")
                else:
                    print(f"  ? {it['name']:<22} (no package mapped for {pm})")
            else:
                print(f"  * {it['name']:<22} {it['note']}")
        print()

    if plan["drivers"]:
        section("Drivers & firmware", plan["drivers"])
    if plan["layers"]:
        section("Compatibility layers", plan["layers"])
    if plan["manual"]:
        section("Manual / experimental", plan["manual"])

    cov = ctx["coverage"]
    print("Resulting app coverage:")
    for k, v in cov.items():
        print(f"  {'✓' if v else '·'} {k}")
    print()

    pkgs = all_packages(plan)
    if pm and pkgs:
        print("Would run:")
        print(f"  sudo {' '.join(INSTALL_CMD[pm])} \\")
        print("    " + " ".join(pkgs))
    print("\n(plan only — nothing installed. Use --install to apply.)")


def do_install(ctx: dict) -> int:
    pm = ctx["pm"]
    if not pm:
        print("error: no supported package manager found.", file=sys.stderr)
        return 2
    if os.geteuid() != 0:
        print("error: --install needs root. Re-run with sudo.", file=sys.stderr)
        return 2
    pkgs = all_packages(ctx["plan"])
    if not pkgs:
        print("Nothing to install.")
        return 0
    print("About to install:\n  " + " ".join(pkgs))
    if input("Proceed? [y/N] ").strip().lower() not in ("y", "yes"):
        print("Aborted.")
        return 1
    cmd = INSTALL_CMD[pm] + pkgs
    print("Running:", " ".join(cmd))
    return subprocess.call(cmd)


# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Freeform Linux Conversion Kit")
    ap.add_argument("--only", choices=["drivers", "layers", "apps"],
                    help="limit the plan to one part")
    ap.add_argument("--json", action="store_true", help="emit JSON plan")
    ap.add_argument("--install", action="store_true",
                    help="actually install (needs sudo; asks first)")
    args = ap.parse_args(argv)

    if platform.system() != "Linux":
        print("error: the conversion kit targets Linux.", file=sys.stderr)
        return 2

    distro = detect_distro()
    pm = detect_pkg_manager()
    gpus = detect_gpus()
    present = detect_layers()
    plan = build_plan(pm, gpus, args.only)
    ctx = {"distro": distro, "pm": pm, "gpus": gpus, "layers_present": present,
           "plan": plan, "coverage": coverage(present, plan)}

    if args.install:
        return do_install(ctx)
    if args.json:
        print(json.dumps(ctx, indent=2))
        return 0
    print_plan(ctx)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
