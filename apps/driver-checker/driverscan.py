#!/usr/bin/env python3
"""Nexus OS — driver checker.

Scans the host for hardware devices and reports, for each one, whether a
driver is currently bound. Devices with no driver are flagged so you can see
what Nexus OS would still need to support.

Pure standard library. No external tools, no pip installs.

Backends:
  - Linux:   reads /sys/bus/*/devices (fully implemented, runs here)
  - Windows: planned — PnP enumeration via SetupAPI / PowerShell Get-PnpDevice
  - macOS:   planned — IORegistry via ioreg

Usage:
  python3 driverscan.py            # human-readable report
  python3 driverscan.py --json     # machine-readable (for the UI)
  python3 driverscan.py --missing  # only devices with no driver bound
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import sys
from dataclasses import dataclass, asdict


@dataclass
class Device:
    bus: str                 # pci, usb, platform, virtio, ...
    name: str                # sysfs node / address
    description: str         # best-effort human label
    vendor_id: str | None
    device_id: str | None
    driver: str | None       # bound driver/module, or None
    modalias: str | None     # kernel match string
    physical: bool = True    # real hardware vs virtual kernel object

    @property
    def has_driver(self) -> bool:
        return bool(self.driver)


# --------------------------------------------------------------------------- #
# Linux backend                                                               #
# --------------------------------------------------------------------------- #
SYS_BUS = "/sys/bus"

# Buses that represent real, attachable hardware. Everything else in /sys/bus
# (memory, cpu, clockevents, workqueue, node, event_source, ...) is a virtual
# kernel object that never binds a "driver" in the sense Nexus OS cares about,
# so it would only add noise to the missing-driver count.
PHYSICAL_BUSES = {
    "pci", "usb", "virtio", "hid", "platform", "pnp",
    "serial", "serial-base", "acpi", "mdio_bus", "scsi",
    "i2c", "spi", "mmc", "sdio", "thunderbolt",
}


def _read(path: str) -> str | None:
    try:
        with open(path, "r", errors="replace") as fh:
            return fh.read().strip()
    except (OSError, ValueError):
        return None


def _driver_of(dev_path: str) -> str | None:
    link = os.path.join(dev_path, "driver")
    if os.path.islink(link):
        return os.path.basename(os.readlink(link))
    return None


def _describe(bus: str, dev_path: str, modalias: str | None) -> str:
    # Try a few common sysfs fields for a friendly label.
    for field in ("product", "name", "model", "label"):
        val = _read(os.path.join(dev_path, field))
        if val:
            return val
    uevent = _read(os.path.join(dev_path, "uevent")) or ""
    for line in uevent.splitlines():
        if line.startswith(("DRIVER=", "PCI_CLASS=", "OF_FULLNAME=")):
            return line.split("=", 1)[1]
    return modalias or f"{bus} device"


def scan_linux(only_missing: bool = False, include_virtual: bool = False) -> list[Device]:
    devices: list[Device] = []
    if not os.path.isdir(SYS_BUS):
        return devices

    for bus in sorted(os.listdir(SYS_BUS)):
        physical = bus in PHYSICAL_BUSES
        if not physical and not include_virtual:
            continue
        dev_dir = os.path.join(SYS_BUS, bus, "devices")
        if not os.path.isdir(dev_dir):
            continue
        for entry in sorted(os.listdir(dev_dir)):
            dev_path = os.path.realpath(os.path.join(dev_dir, entry))
            modalias = _read(os.path.join(dev_path, "modalias"))
            vendor = _read(os.path.join(dev_path, "vendor")) or \
                _read(os.path.join(dev_path, "idVendor"))
            device = _read(os.path.join(dev_path, "device")) or \
                _read(os.path.join(dev_path, "idProduct"))
            driver = _driver_of(dev_path)
            if only_missing and driver:
                continue
            devices.append(Device(
                bus=bus,
                name=entry,
                description=_describe(bus, dev_path, modalias),
                vendor_id=vendor,
                device_id=device,
                driver=driver,
                modalias=modalias,
                physical=physical,
            ))
    return devices


# --------------------------------------------------------------------------- #
# Stubs for other platforms (documented, not yet implemented)                 #
# --------------------------------------------------------------------------- #
def scan_windows(only_missing: bool = False) -> list[Device]:
    raise NotImplementedError(
        "Windows backend not implemented yet. Plan: enumerate PnP devices via "
        "`powershell Get-PnpDevice` (or SetupAPI) and read Problem codes to "
        "detect missing/failed drivers. See docs/DRIVERS.md."
    )


def scan_macos(only_missing: bool = False) -> list[Device]:
    raise NotImplementedError(
        "macOS backend not implemented yet. Plan: parse `ioreg -l` for the "
        "IORegistry tree and each node's bound IOService class. "
        "See docs/DRIVERS.md."
    )


def scan(only_missing: bool = False, include_virtual: bool = False) -> list[Device]:
    system = platform.system()
    if system == "Linux":
        return scan_linux(only_missing, include_virtual)
    if system == "Windows":
        return scan_windows(only_missing)
    if system == "Darwin":
        return scan_macos(only_missing)
    raise NotImplementedError(f"Unsupported platform: {system}")


# --------------------------------------------------------------------------- #
# Reporting                                                                   #
# --------------------------------------------------------------------------- #
def print_report(devices: list[Device]) -> None:
    total = len(devices)
    bound = sum(1 for d in devices if d.has_driver)
    missing = total - bound

    print(f"Nexus OS driver checker — {platform.system()} "
          f"({platform.machine()})")
    print("=" * 62)
    print(f"{total} devices   {bound} with driver   {missing} missing\n")

    by_bus: dict[str, list[Device]] = {}
    for d in devices:
        by_bus.setdefault(d.bus, []).append(d)

    for bus in sorted(by_bus):
        print(f"[{bus}]")
        for d in by_bus[bus]:
            flag = "ok " if d.has_driver else "!! "
            drv = d.driver or "— NO DRIVER —"
            ids = ""
            if d.vendor_id or d.device_id:
                ids = f"  {d.vendor_id or '?'}:{d.device_id or '?'}"
            print(f"  {flag}{d.name:<22} {drv:<18}{ids}")
            print(f"       {d.description}")
        print()

    if missing:
        print(f"{missing} device(s) have no driver bound — these are the gaps "
              f"Nexus OS must cover.")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Nexus OS driver checker")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--missing", action="store_true",
                    help="only devices with no driver bound")
    ap.add_argument("--all", action="store_true",
                    help="include virtual kernel objects (cpu, memory, ...)")
    args = ap.parse_args(argv)

    try:
        devices = scan(only_missing=args.missing, include_virtual=args.all)
    except NotImplementedError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = {
            "system": platform.system(),
            "machine": platform.machine(),
            "total": len(devices),
            "with_driver": sum(1 for d in devices if d.has_driver),
            "missing": sum(1 for d in devices if not d.has_driver),
            "devices": [asdict(d) for d in devices],
        }
        print(json.dumps(payload, indent=2))
    else:
        print_report(devices)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
