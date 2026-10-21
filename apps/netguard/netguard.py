#!/usr/bin/env python3
"""Freeform OS — NetGuard: Mullvad auto-connect + Tor + fail-closed kill switch.

Three jobs:
  1. Auto-connect Mullvad on boot, with its lockdown (kill-switch) mode on.
  2. A FAIL-CLOSED firewall: all outbound traffic is dropped unless it goes
     through the VPN tunnel. Because the default policy is DROP, there is NO
     leak window — if the tunnel dies, packets are already blocked (0 ms).
  3. A watchdog that, on tunnel loss, also kills the radios (Wi-Fi/Bluetooth/
     cellular) via rfkill so "all signals going out shut off" physically.

Safe by default: prints the PLAN and the exact firewall ruleset, changing
nothing. Pass --arm to apply (needs root). Pure standard library.

  python3 netguard.py                 # show plan + generated nftables ruleset
  sudo python3 netguard.py --arm      # apply kill switch + auto-connect
  sudo python3 netguard.py --watchdog # run the tunnel watchdog (radio cutoff)
  sudo python3 netguard.py --disarm   # remove the kill switch

Why fail-closed beats "detect then disconnect": a reactive kill switch polls,
so there's a window (ms–seconds) where traffic leaks before it reacts. Default
DROP has no window. The watchdog is only the *extra* radio-off step.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time

WG_IFACE = "wg0"          # WireGuard/Mullvad tunnel interface
WG_PORT = 51820           # Mullvad WireGuard port (also uses 53, 4000-33000 for some)
TABLE = "freeform_killswitch"


# --------------------------------------------------------------------------- #
# Detection                                                                    #
# --------------------------------------------------------------------------- #
def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def discover_endpoints() -> list[str]:
    """Mullvad server IPs we must allow (so the handshake can happen)."""
    eps: list[str] = []
    # from any wireguard config on disk
    confdir = "/etc/wireguard"
    if os.path.isdir(confdir):
        for f in os.listdir(confdir):
            if f.endswith(".conf"):
                try:
                    for line in open(os.path.join(confdir, f)):
                        if line.strip().lower().startswith("endpoint"):
                            host = line.split("=", 1)[1].strip().split(":")[0]
                            eps.append(host)
                except OSError:
                    pass
    return sorted(set(eps))


# --------------------------------------------------------------------------- #
# Firewall ruleset (nftables, fail-closed)                                     #
# --------------------------------------------------------------------------- #
def build_ruleset(endpoints: list[str], allow_lan: bool) -> str:
    ep = ", ".join(endpoints) if endpoints else "0.0.0.0/32"  # none known -> allow nothing extra
    ep_line = (f"        ip daddr {{ {ep} }} udp dport {WG_PORT} accept   # to Mullvad server\n"
               if endpoints else
               "        # (no VPN endpoint discovered yet — add it to /etc/wireguard/*.conf)\n")
    lan = ("        ip daddr {{ 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 }} accept  # LAN\n"
           if allow_lan else "")
    lan_in = ("        ip saddr {{ 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 }} accept\n"
              if allow_lan else "")
    return f"""\
table inet {TABLE} {{
  chain output {{
    type filter hook output priority 0; policy drop;          # FAIL-CLOSED
    oifname "lo" accept
    oifname "{WG_IFACE}" accept                               # anything inside the tunnel
    ct state established,related accept
{ep_line}        udp dport 67 accept                                       # DHCP
{lan}    }}
  chain input {{
    type filter hook input priority 0; policy drop;
    iifname "lo" accept
    iifname "{WG_IFACE}" accept
    ct state established,related accept
{lan_in}    }}
}}
"""


# --------------------------------------------------------------------------- #
# Actions                                                                      #
# --------------------------------------------------------------------------- #
def run(cmd: list[str], dry: bool) -> int:
    print(("DRY  " if dry else "RUN  ") + " ".join(cmd))
    if dry:
        return 0
    return subprocess.call(cmd)


def require_root() -> bool:
    if os.geteuid() != 0:
        print("error: needs root. Re-run with sudo.", file=sys.stderr)
        return False
    return True


def arm(endpoints: list[str], allow_lan: bool, dry: bool) -> int:
    if not dry and not require_root():
        return 2
    ruleset = build_ruleset(endpoints, allow_lan)

    # 1) Mullvad kill switch + auto-connect (its own lockdown is the first line)
    if have("mullvad"):
        run(["mullvad", "lockdown-mode", "set", "on"], dry)   # block when disconnected
        run(["mullvad", "auto-connect", "set", "on"], dry)    # connect on boot
        run(["mullvad", "connect"], dry)
    else:
        print("note: mullvad CLI not found — relying on the nftables kill switch "
              "and your WireGuard config.")

    # 2) Our fail-closed nftables layer (works even if Mullvad app isn't managing it)
    if have("nft"):
        if dry:
            print("DRY  nft -f - <<'RULES'\n" + ruleset + "RULES")
        else:
            p = subprocess.run(["nft", "-f", "-"], input=ruleset, text=True)
            if p.returncode != 0:
                return p.returncode
    else:
        print("error: nftables (nft) not installed — cannot apply kill switch.",
              file=sys.stderr)
        return 2

    print("\nKill switch ARMED (fail-closed). If the tunnel drops, outbound "
          "traffic is already blocked — no leak window.")
    return 0


def disarm(dry: bool) -> int:
    if not dry and not require_root():
        return 2
    if have("mullvad"):
        run(["mullvad", "lockdown-mode", "set", "off"], dry)
    if have("nft"):
        run(["nft", "delete", "table", "inet", TABLE], dry)
    print("Kill switch disarmed.")
    return 0


def tunnel_up() -> bool:
    """True if the WG interface exists and has carrier."""
    path = f"/sys/class/net/{WG_IFACE}"
    if not os.path.isdir(path):
        return False
    # a wg interface is 'unknown' operstate; treat presence + a recent handshake as up
    if have("wg"):
        try:
            out = subprocess.check_output(["wg", "show", WG_IFACE, "latest-handshakes"],
                                          text=True, stderr=subprocess.DEVNULL)
            for line in out.splitlines():
                ts = int(line.split()[-1])
                if ts and (time.time() - ts) < 180:
                    return True
            return False
        except (subprocess.CalledProcessError, ValueError, IndexError):
            return False
    return True


def watchdog(interval: float, dry: bool) -> int:
    if not dry and not require_root():
        return 2
    print(f"Watchdog running (every {interval}s). On tunnel loss: rfkill block all.")
    radios_off = False
    try:
        while True:
            up = tunnel_up()
            if not up and not radios_off:
                print("!! tunnel DOWN — cutting all radios now")
                if have("rfkill"):
                    run(["rfkill", "block", "all"], dry)        # wifi/bt/cell off
                if have("nmcli"):
                    run(["nmcli", "networking", "off"], dry)
                radios_off = True
            elif up and radios_off:
                print("tunnel restored — radios remain off until you re-enable "
                      "(rfkill unblock all).")
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\nwatchdog stopped.")
        return 0


# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Freeform OS NetGuard kill switch")
    ap.add_argument("--arm", action="store_true", help="apply kill switch + auto-connect")
    ap.add_argument("--disarm", action="store_true", help="remove the kill switch")
    ap.add_argument("--watchdog", action="store_true", help="run the radio-cutoff watchdog")
    ap.add_argument("--allow-lan", action="store_true",
                    help="still allow local LAN (printers, NAS) when armed")
    ap.add_argument("--interval", type=float, default=1.0, help="watchdog poll seconds")
    args = ap.parse_args(argv)

    if sys.platform != "linux" and not sys.platform.startswith("linux"):
        print("error: NetGuard targets Linux.", file=sys.stderr)
        return 2

    endpoints = discover_endpoints()

    if args.disarm:
        return disarm(dry=False)
    if args.watchdog:
        return watchdog(args.interval, dry=False)
    if args.arm:
        return arm(endpoints, args.allow_lan, dry=False)

    # default: dry plan
    print("Freeform OS — NetGuard (plan only, nothing applied)")
    print("=" * 58)
    print(f"mullvad CLI : {'found' if have('mullvad') else 'not found'}")
    print(f"nftables    : {'found' if have('nft') else 'MISSING (required)'}")
    print(f"rfkill      : {'found' if have('rfkill') else 'not found'}")
    print(f"WG iface    : {WG_IFACE}")
    print(f"Endpoints   : {', '.join(endpoints) if endpoints else 'none discovered'}")
    print()
    print("Would run (arm):")
    arm(endpoints, args.allow_lan, dry=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
