#!/usr/bin/env python3
"""Freeform OS — shellkit: the command registry behind /help.

Builds one catalog of commands for the loaded distro by combining:
  1. base commands (distros/commands/base.json) — always present, incl. the
     custom Freeform commands (/help, /distro, freefetch),
  2. the distro's curated commands (e.g. commands/kali.json),
  3. an AUTO-SCAN of the live system's $PATH — every executable actually
     installed, so nothing is missed. Scanned-only commands get their one-line
     description from `whatis` when available.

Usage:
  python3 shellkit.py help                 # the /help screen
  python3 shellkit.py help --distro kali   # help for a specific distro
  python3 shellkit.py scan                 # how many commands found where
  python3 shellkit.py json                 # full catalog as JSON
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DISTRO_DIR = os.path.join(ROOT, "distros")


def _load_json(path: str) -> dict:
    try:
        with open(path) as fh:
            data = json.load(fh)
        return {k: v for k, v in data.items() if not k.startswith("_")}
    except (OSError, ValueError):
        return {}


def load_registry() -> dict:
    return _load_json(os.path.join(DISTRO_DIR, "registry.json"))


def resolve_distro(distro_id: str | None) -> dict:
    reg = load_registry()
    want = distro_id or reg.get("default", "ubuntu")
    for d in reg.get("recommended", []) + reg.get("custom", []):
        if d.get("id") == want:
            return d
    return {"id": want, "name": want, "commands": ""}


def scan_path() -> list[str]:
    """Every executable name on $PATH (deduped, sorted)."""
    found: set[str] = set()
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d or not os.path.isdir(d):
            continue
        try:
            for name in os.listdir(d):
                full = os.path.join(d, name)
                if os.path.isfile(full) and os.access(full, os.X_OK):
                    found.add(name)
        except OSError:
            continue
    return sorted(found)


def whatis(cmd: str) -> str:
    if not shutil.which("whatis"):
        return ""
    try:
        out = subprocess.check_output(["whatis", cmd], text=True,
                                      stderr=subprocess.DEVNULL, timeout=2)
        line = out.splitlines()[0]
        if " - " in line:
            return line.split(" - ", 1)[1].strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, IndexError):
        pass
    return ""


def build_catalog(distro: dict, enrich: bool = False) -> dict:
    catalog: dict[str, dict] = {}

    def add(name, desc, source):
        if name in catalog and catalog[name]["desc"]:
            return
        catalog[name] = {"desc": desc, "source": source}

    for name, desc in _load_json(os.path.join(DISTRO_DIR, "commands", "base.json")).items():
        add(name, desc, "base")

    rel = distro.get("commands", "")
    if rel:
        for name, desc in _load_json(os.path.join(DISTRO_DIR, rel)).items():
            add(name, desc, distro.get("id", "distro"))

    for name in scan_path():
        if name not in catalog:
            add(name, whatis(name) if enrich else "", "scanned")

    return catalog


def print_help(distro: dict, catalog: dict) -> None:
    documented = {k: v for k, v in catalog.items() if v["desc"]}
    scanned = sorted(k for k, v in catalog.items() if not v["desc"])
    print(f"FreeForm OS — /help    (distro: {distro.get('name', '?')})")
    print("=" * 60)
    print(f"{len(catalog)} commands available "
          f"({len(documented)} documented, {len(scanned)} more on PATH)\n")
    for name in sorted(documented):
        tag = "" if documented[name]["source"] in ("base", distro.get("id")) else " ·"
        print(f"  {name:<16} {documented[name]['desc']}{tag}")
    if scanned:
        print(f"\nAlso installed (run `<cmd> --help` for details):")
        # wrap the scanned list
        line = "  "
        for name in scanned:
            if len(line) + len(name) + 2 > 76:
                print(line); line = "  "
            line += name + "  "
        if line.strip():
            print(line)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Freeform OS command registry")
    ap.add_argument("action", nargs="?", default="help",
                    choices=["help", "scan", "json"])
    ap.add_argument("--distro", default=None)
    ap.add_argument("--enrich", action="store_true",
                    help="look up descriptions for scanned commands via whatis")
    args = ap.parse_args(argv)

    distro = resolve_distro(args.distro)
    catalog = build_catalog(distro, enrich=args.enrich)

    if args.action == "scan":
        by = {}
        for v in catalog.values():
            by[v["source"]] = by.get(v["source"], 0) + 1
        print(f"Distro: {distro.get('name')}  ({distro.get('id')})")
        print("Commands by source:")
        for k, n in sorted(by.items()):
            print(f"  {k:<10} {n}")
        print(f"  {'TOTAL':<10} {len(catalog)}")
    elif args.action == "json":
        print(json.dumps({"distro": distro, "commands": catalog}, indent=2))
    else:
        print_help(distro, catalog)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
