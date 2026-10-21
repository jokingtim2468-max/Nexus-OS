#!/usr/bin/env python3
"""freefetch — Freeform OS system info (fastfetch-style logo + specs).

Prints an ASCII logo next to live system specs. Pure standard library, so it
runs on any distro Freeform loads. The logo/accent can be overridden per distro
by the loader (see distros/registry.json -> "logo").

Usage:
  python3 freefetch.py            # logo + specs
  python3 freefetch.py --json     # specs as JSON
  python3 freefetch.py --logo kali   # force a distro logo
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import time

# Small ASCII logos keyed by distro id (ascii-safe, 6 lines each).
LOGOS = {
    "freeform": [
        " ███████ ███████ ",
        " ██      ██      ",
        " █████   █████   ",
        " ██      ██      ",
        " ██      ██      ",
        "   FreeForm OS   ",
    ],
    "kali": [
        "  ..,,,,..  ",
        " .df Kali b.",
        " `?WWWWWW?' ",
        "   `??''    ",
        "   dragon   ",
        "            ",
    ],
    "ubuntu": [
        "   _    ",
        "  (o)   ",
        " <  o)  ",
        "  (o)   ",
        "   -    ",
        "        ",
    ],
    "generic": [
        "  ____  ",
        " |  _ \\ ",
        " | | | |",
        " | |_| |",
        " |____/ ",
        "        ",
    ],
}


def _read(path: str) -> str:
    try:
        with open(path, errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def distro() -> dict:
    kv = {}
    for line in _read("/etc/os-release").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k] = v.strip().strip('"')
    return {"name": kv.get("PRETTY_NAME") or kv.get("NAME", "Linux"),
            "id": kv.get("ID", "linux")}


def cpu() -> str:
    model, count = "Unknown CPU", 0
    for line in _read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            model = line.split(":", 1)[1].strip()
        if line.startswith("processor"):
            count += 1
    return f"{model} ({count} cores)" if count else model


def memory() -> str:
    total = avail = 0
    for line in _read("/proc/meminfo").splitlines():
        if line.startswith("MemTotal:"):
            total = int(line.split()[1])
        elif line.startswith("MemAvailable:"):
            avail = int(line.split()[1])
    if not total:
        return "Unknown"
    used = (total - avail) / 1024 / 1024
    return f"{used:.1f} / {total/1024/1024:.1f} GiB"


def uptime() -> str:
    raw = _read("/proc/uptime").split()
    if not raw:
        return "Unknown"
    secs = int(float(raw[0]))
    h, m = secs // 3600, (secs % 3600) // 60
    return f"{h}h {m}m"


def collect() -> dict:
    d = distro()
    return {
        "os": d["name"],
        "id": d["id"],
        "host": platform.node(),
        "kernel": platform.release(),
        "arch": platform.machine(),
        "uptime": uptime(),
        "shell": os.environ.get("SHELL", "unknown").split("/")[-1],
        "cpu": cpu(),
        "memory": memory(),
        "freeform": "Freeform OS shell",
    }


def render(info: dict, logo_id: str) -> str:
    logo = LOGOS.get(logo_id) or LOGOS.get(info["id"]) or LOGOS["generic"]
    rows = [
        ("", f"{info['freeform']}"),
        ("OS", info["os"]),
        ("Host", info["host"]),
        ("Kernel", info["kernel"]),
        ("Arch", info["arch"]),
        ("Uptime", info["uptime"]),
        ("Shell", info["shell"]),
        ("CPU", info["cpu"]),
        ("Memory", info["memory"]),
    ]
    lines = []
    for i in range(max(len(logo), len(rows))):
        left = logo[i] if i < len(logo) else " " * len(logo[0])
        if i < len(rows):
            key, val = rows[i]
            right = f"{key}: {val}" if key else val
        else:
            right = ""
        lines.append(f"{left}  {right}")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="freefetch — Freeform OS system info")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--logo", default=None, help="force a distro logo id")
    args = ap.parse_args(argv)
    info = collect()
    if args.json:
        print(json.dumps(info, indent=2))
    else:
        print(render(info, args.logo or "freeform"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
