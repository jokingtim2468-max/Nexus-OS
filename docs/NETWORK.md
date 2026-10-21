# Freeform OS — network privacy (Mullvad + Tor + kill switch)

Implemented as a real tool: `apps/netguard/netguard.py` (safe by default —
prints the plan; `--arm` applies). Nothing in the UI is "connected" until this
runs on the target machine.

## Decision on the theme (context)
We are **not** forking WhiteSur. It's GPL-3.0, which would force the whole
project to stay copyleft and credit upstream — a tailoring constraint we don't
want. We keep our own `ui/theme/macos-tokens.css`, which already matches the
macOS metrics with no license strings. Full freedom to change anything.

## 1. Auto Mullvad connection
- `mullvad auto-connect set on` → connects on boot.
- `mullvad lockdown-mode set on` → Mullvad's own kill switch (first line of
  defense).
- `mullvad connect`.
- WireGuard-based, no-logs, anonymous account (no email). ~€5/month flat — no
  tiers or bandwidth upsell (per owner cost preference).

## 2. Kill switch — fail-closed (the key design)
The firewall (`nftables`) default policy is **DROP** on output. Only these are
allowed out:
- `lo` (loopback),
- the `wg0` tunnel interface (so your real traffic, which rides the tunnel),
- the handshake to the Mullvad **server IPs** on the WG port,
- DHCP, and optionally the LAN (`--allow-lan`).

**Everything else is dropped.** This means:

> There is **no "detect then react" delay.** A reactive kill switch polls the
> link and reacts after a leak window (ms–seconds). Default-DROP has **no
> window at all** — the moment traffic isn't going through `wg0`, it's already
> blocked. Shortest possible = **zero**, because it was never allowed.

## 3. "All signals going out shut off" — radio cutoff
On top of fail-closed firewalling, the **watchdog** (`--watchdog`) checks the
tunnel's last WireGuard handshake every second; if the tunnel is down it
immediately:
- `rfkill block all` → turns off Wi-Fi, Bluetooth, and cellular radios,
- `nmcli networking off` → drops NetworkManager connectivity.

So within ~1s of a tunnel failure the radios are physically off, and in the
meantime the firewall already blocked any packet. Radios stay off until you
`rfkill unblock all` on purpose (fail-safe, not auto-reconnect into the clear).

## 4. Tor routing
Design: **Mullvad → Tor** (connect Mullvad first, then route app traffic through
Tor).
- **Easiest & robust:** use the **Mullvad Browser** (a Tor-Browser fork) or
  Tor Browser for the traffic you want over Tor, while Mullvad covers the rest.
- **Per-app:** `torsocks <app>` routes a single app through Tor's SOCKS proxy
  (127.0.0.1:9050).
- **System-wide transparent Tor** is possible (nftables redirect to Tor's
  TransPort 9040 + DNSPort) but **fragile** — Tor is slow, many apps/sites break
  or block it, and UDP can't go over Tor. So per-app Tor is the sane default.
  (You already guessed system-wide probably won't work — correct.)

## Honest status
- `netguard.py` is real and runnable; it changes the firewall and radios, so it
  needs root and is **plan-only by default**.
- The UI "Mullvad / Tor / Kill Switch" tiles are **indicators** — they reflect
  what NetGuard would manage, not a live connection, until the shell is wired to
  call NetGuard.

## Usage
```bash
python3 apps/netguard/netguard.py              # show plan + the exact ruleset
sudo python3 apps/netguard/netguard.py --arm   # Mullvad autoconnect + kill switch
sudo python3 apps/netguard/netguard.py --watchdog   # radio cutoff on tunnel loss
sudo python3 apps/netguard/netguard.py --disarm
```
