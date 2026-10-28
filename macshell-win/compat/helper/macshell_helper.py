#!/usr/bin/env python3
"""macshell-helper — the system backend behind MacShell's network / Bluetooth UI.

MacShell's QML (MacBar.qml, MacDock.qml) used to run Linux tools (nmcli, bluetoothctl,
rfkill) and parse their text. On Windows those don't exist, so each of those call sites
now runs `macshell-helper <command>` instead, and this program prints **the same text
format** the QML already parses. MacShell's UI and parsing code stay unchanged.

Backends (MACSHELL_HELPER_BACKEND = windows | linux | mock, default: by platform):
  windows  native Windows APIs via winnet.ps1 (PowerShell 5.1 + WinRT)
  linux    MacShell's original shell commands, verbatim (keeps upstream behaviour)
  mock     a JSON state file (MACSHELL_HELPER_MOCK) for tests and the reference rig

Commands (what the QML calls):
  net status | net devices | net ethernet
  wifi radio on|off | wifi list | wifi connect SSID [password PW] | wifi disconnect
  conn list | conn up|down NAME
  bt status | bt power on|off | bt scan | bt connect MAC | bt disconnect MAC | bt forget MAC
  airplane on|off
  store search|list|updates|install|uninstall|update ...   (the App Store app; see store.py)
  wallpaper scan DIR MAKE [FAV...] | wallpaper set FILE   (Settings > Wallpaper; see wallpaper.py)
  wallpaper engine status|list|apply FILE [MONITOR]|stop    (Wallpaper Engine; see wallpaper_engine.py)
  about                                                   ("About This PC" facts; see about.py)
  apps sync                                               (Start Menu apps -> .desktop files; see apps.py)
  theme list | theme apply black|white|graphite|default     (Windows/GTK app mode + Spotify; see theme.py)
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


# ─────────────────────────── output formats (what MacShell parses) ───────────────────────────
def esc(s):
    """nmcli -t escaping: backslash and colon are backslash-escaped."""
    return str(s).replace("\\", "\\\\").replace(":", "\\:")


def fmt_net_status(st):
    # MacBar.qml wifiProc: line0 radio, line1 "yes:SSID:SIGNAL" (or empty), ..., a line "eth" when wired
    lines = ["enabled" if st["wifi_on"] else "disabled",
             f"yes:{esc(st['ssid'])}:{int(st['signal'])}" if st.get("ssid") else "",
             "",
             "eth" if st.get("ethernet_up") else "-"]
    return "\n".join(lines) + "\n"


def fmt_wifi_list(wl):
    # MacBar.qml wifiListProc: "S:<saved profile>" and "N:<in-use>:<ssid>:<signal>:<security>"
    out = [f"S:{esc(s)}" for s in wl.get("saved", [])]
    for n in wl.get("networks", []):
        out.append("N:%s:%s:%d:%s" % ("*" if n.get("inUse") else "", esc(n["ssid"]),
                                       int(n.get("signal", 0)), "WPA2" if n.get("secure") else "--"))
    return "\n".join(out) + ("\n" if out else "")


def fmt_conn_list(c):
    # MacBar.qml connProc: "NAME:TYPE:DEVICE" with DEVICE "--" when inactive
    out = []
    for e in c.get("eth", []):
        out.append(f"{esc(e['name'])}:802-3-ethernet:{esc(e.get('device') or e['name']) if e.get('up') else '--'}")
    for v in c.get("vpn", []):
        out.append(f"{esc(v['name'])}:vpn:{'vpn0' if v.get('connected') else '--'}")
    return "\n".join(out) + ("\n" if out else "")


def fmt_net_devices(c, st):
    # MacDock.qml netProc (Settings > Network): "dev\ttype\tstate\tconnection\tip"
    out = [f"{e['name']}\tethernet\t{'connected' if e.get('up') else 'unavailable'}\t"
           f"{e['name'] if e.get('up') else ''}\t{e.get('ip', '')}" for e in c.get("eth", [])]
    if st is not None:
        out.append(f"Wi-Fi\twifi\t{'connected' if st.get('ssid') else ('disconnected' if st['wifi_on'] else 'unavailable')}"
                   f"\t{st.get('ssid', '')}\t")
    return "\n".join(out) + ("\n" if out else "")


def fmt_net_ethernet(c):
    # MacDock.qml ethProc (Settings > Wi-Fi): first Ethernet "dev\tstate\tconnection\tip\tspeed-Mbps"
    for e in c.get("eth", []):
        return (f"{e['name']}\t{'connected' if e.get('up') else 'unavailable'}\t"
                f"{e['name'] if e.get('up') else ''}\t{e.get('ip', '')}\t{e.get('speed', '')}")
    return ""


def fmt_bt_status(bt):
    # MacBar.qml btProc: "P:Powered: yes|no", then "D:mac\tpaired\tconnected\tbattery\tname"
    out = [f"P:Powered: {'yes' if bt.get('on') else 'no'}"]
    for d in bt.get("devices", []):
        out.append("D:%s\t%d\t%d\t%s\t%s" % (d["mac"], 1 if d.get("paired") else 0,
                                            1 if d.get("connected") else 0, d.get("battery", ""), d["name"]))
    return "\n".join(out) + "\n"


# ─────────────────────────── backends ───────────────────────────
class Fail(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


class WindowsBackend:
    PS = os.path.join(HERE, "winnet.ps1")

    def _ps(self, *args, want_json=True):
        cmd = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
               "-File", self.PS, *args]
        flags = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW: no console flash
        r = subprocess.run(cmd, capture_output=True, text=True, creationflags=flags)
        if r.returncode != 0:
            raise Fail((r.stderr or r.stdout).strip() or "failed", r.returncode)
        return json.loads(r.stdout) if want_json else None

    def status(self):        return self._ps("status")
    def wifi_list(self):     return self._ps("wifilist")
    def conns(self):         return self._ps("conns")
    # `bt scan` and `bt status` are separate processes, so nearby (unpaired) devices found by a
    # scan are kept in a small cache file and listed by `bt status` for a minute.
    NEARBY = os.path.join(os.environ.get("TEMP", HERE), "macshell-bt-nearby.json")

    def _nearby(self):
        try:
            with open(self.NEARBY, encoding="utf-8") as fh:
                d = json.load(fh)
            return d["devices"] if time.time() - d["at"] < 60 else []
        except (OSError, ValueError, KeyError):
            return []

    def bt(self):
        r = self._ps("bt")
        known = {d["mac"] for d in r.get("devices", [])}
        r["devices"] = r.get("devices", []) + [d for d in self._nearby() if d["mac"] not in known]
        return r
    def wifi_radio(self, on): self._ps("radio", "wifi", "on" if on else "off", want_json=False)
    def bt_power(self, on):  self._ps("radio", "bluetooth", "on" if on else "off", want_json=False)
    def airplane(self, on):  self._ps("airplane", "on" if on else "off", want_json=False)
    def wifi_connect(self, ssid, pw): self._ps("wificonnect", ssid, *([pw] if pw else []), want_json=False)
    def wifi_disconnect(self): self._ps("wifidisconnect", want_json=False)
    def conn(self, up, name): self._ps("conn", "up" if up else "down", name, want_json=False)
    def bt_scan(self):
        found = self._ps("btscan").get("devices", [])
        with open(self.NEARBY, "w", encoding="utf-8") as fh:
            json.dump({"at": time.time(), "devices": found}, fh)

    def bt_connect(self, mac, connect):
        if connect and any(d["mac"] == mac for d in self._nearby()):
            self._ps("btpair", mac, want_json=False)     # a new device: pairing connects it
            return
        # Windows has no public API to force a paired device to (dis)connect; it reconnects
        # paired devices automatically when they are switched on.
        raise Fail("Windows connects paired devices automatically. Switch the device on, or "
                   "use Bluetooth settings to pair a new one.", 2)

    def bt_forget(self, mac): self._ps("btforget", mac, want_json=False)


class MockBackend:
    """State lives in a JSON file; actions change it. Used by tests and the reference rig."""
    DEFAULT = {
        "wifi_on": True, "ssid": "", "signal": 0, "ethernet_up": True,
        "networks": [{"ssid": "Home-5G", "signal": 82, "secure": True},
                     {"ssid": "Neighbour", "signal": 40, "secure": True},
                     {"ssid": "Cafe Guest", "signal": 30, "secure": False}],
        "saved": ["Home-5G"], "passwords": {"Home-5G": "hunter22"},
        "eth": [{"name": "Ethernet", "device": "Realtek PCIe GbE", "up": True, "ip": "192.168.1.20", "speed": 1000}],
        "vpn": [{"name": "Mullvad", "connected": True}],
        "bt_on": True,
        "devices": [{"mac": "AA:BB:CC:00:11:22", "name": "AirPods Pro", "paired": True, "connected": True, "battery": "80"},
                    {"mac": "AA:BB:CC:33:44:55", "name": "MX Master 3", "paired": True, "connected": False, "battery": ""}],
        # in range but never paired; shows up after `bt scan`
        "nearby": [{"mac": "AA:BB:CC:66:77:88", "name": "JBL Flip 6", "paired": False, "connected": False, "battery": ""}],
        "scanned": False,
    }

    def __init__(self, path):
        self.path = path
        try:
            with open(path, encoding="utf-8") as fh:
                self.s = {**self.DEFAULT, **json.load(fh)}
        except (OSError, ValueError):
            self.s = json.loads(json.dumps(self.DEFAULT))

    def _save(self):
        with open(self.path, "w", encoding="utf-8") as fh:
            json.dump(self.s, fh, indent=2)

    def status(self):
        s = self.s
        return {"wifi_on": s["wifi_on"], "ssid": s["ssid"] if s["wifi_on"] else "",
                "signal": s["signal"], "ethernet_up": any(e["up"] for e in s["eth"])}

    def wifi_list(self):
        s = self.s
        if not s["wifi_on"]:
            return {"networks": [], "saved": s["saved"]}
        return {"networks": [{**n, "inUse": n["ssid"] == s["ssid"]} for n in s["networks"]], "saved": s["saved"]}

    def conns(self):  return {"eth": self.s["eth"], "vpn": self.s["vpn"]}
    def bt(self):
        if not self.s["bt_on"]:
            return {"on": False, "devices": []}
        if self.s["scanned"]:   # scanned devices join the list as unpaired, like BlueZ
            macs = {d["mac"] for d in self.s["devices"]}
            self.s["devices"] += [dict(d) for d in self.s["nearby"] if d["mac"] not in macs]
            self.s["scanned"] = False
            self._save()
        return {"on": True, "devices": self.s["devices"]}

    def wifi_radio(self, on):
        self.s["wifi_on"] = on
        if not on:
            self.s["ssid"], self.s["signal"] = "", 0
        self._save()

    def bt_power(self, on): self.s["bt_on"] = on; self._save()

    def airplane(self, on):
        self.s["bt_on"] = self.s["wifi_on"] = not on
        if on:
            self.s["ssid"] = ""
        self._save()

    def wifi_connect(self, ssid, pw):
        n = next((n for n in self.s["networks"] if n["ssid"] == ssid), None)
        if n is None:
            raise Fail(f"Error: No network with SSID '{ssid}' found.", 10)
        known = self.s.get("passwords", {}).get(ssid)
        if n["secure"] and pw != known and ssid not in self.s["saved"]:
            raise Fail("Error: Secrets were required, but not provided.", 4)
        self.s.update(ssid=ssid, signal=n["signal"])
        if ssid not in self.s["saved"]:
            self.s["saved"].append(ssid)
        self._save()

    def wifi_disconnect(self): self.s.update(ssid="", signal=0); self._save()

    def conn(self, up, name):
        for e in self.s["eth"]:
            if e["name"] == name:
                e["up"] = up
        for v in self.s["vpn"]:
            if v["name"] == name:
                v["connected"] = up
        self._save()

    def bt_scan(self): self.s["scanned"] = True; self._save()

    def bt_connect(self, mac, connect):
        for d in self.s["devices"]:
            if d["mac"] == mac:
                d["connected"] = connect
                if connect:
                    d["paired"] = True
        self._save()

    def bt_forget(self, mac):
        self.s["devices"] = [d for d in self.s["devices"] if d["mac"] != mac]
        self._save()


# MacShell's original Linux commands, copied verbatim from MacBar.qml / MacDock.qml.
LINUX = {
    "net status": "nmcli radio wifi 2>/dev/null; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -n1; echo; nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q '^ethernet:connected$' && echo eth || echo -",
    "wifi list": "nmcli dev wifi rescan >/dev/null 2>&1; nmcli -t -f NAME,TYPE connection show 2>/dev/null | sed -n 's/:802-11-wireless$//p' | sed 's/^/S:/'; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null | sed 's/^/N:/'",
    "wifi disconnect": "nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | cut -d: -f1 | head -n1 | xargs -r nmcli dev disconnect",
    "conn list": "nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null",
    "net ethernet": "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$2==\"ethernet\"' | head -1 | while IFS=: read -r d t st c; do ip=$(ip -4 -o addr show \"$d\" 2>/dev/null | awk '{print $4}' | head -1); sp=$(cat /sys/class/net/$d/speed 2>/dev/null); printf '%s\t%s\t%s\t%s\t%s' \"$d\" \"$st\" \"$c\" \"$ip\" \"$sp\"; done",
    "net devices": "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | grep -vE ':(loopback|wifi-p2p|bridge):' | while IFS=: read -r d t s c; do ip=$(ip -4 -o addr show \"$d\" 2>/dev/null | awk '{print $4}' | head -1); printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$d\" \"$t\" \"$s\" \"$c\" \"$ip\"; done",
    "bt status": "p=$(timeout 4 bluetoothctl show 2>/dev/null </dev/null | grep -i 'Powered:' | head -n1); echo \"P:$p\"; timeout 4 bluetoothctl devices 2>/dev/null </dev/null | while read -r _ mac name; do [ -n \"$mac\" ] || continue; i=$(timeout 3 bluetoothctl info \"$mac\" 2>/dev/null </dev/null); pr=$(printf '%s\\n' \"$i\" | grep -Ec 'Paired: yes|Bonded: yes'); c=$(printf '%s\\n' \"$i\" | grep -c 'Connected: yes'); b=$(printf '%s\\n' \"$i\" | sed -n 's/.*Battery Percentage: 0x[0-9a-fA-F]* (\\([0-9]*\\)).*/\\1/p' | head -n1); printf 'D:%s\\t%s\\t%s\\t%s\\t%s\\n' \"$mac\" \"$pr\" \"$c\" \"$b\" \"$name\"; done",
    "bt scan": "bluetoothctl --timeout 10 scan on >/dev/null 2>&1 </dev/null; exit 0",
    "bt power on": "rfkill unblock bluetooth 2>/dev/null; sleep 0.3; bluetoothctl power on",
    "bt power off": "bluetoothctl power off",
    "airplane on": "rfkill block all",
    "airplane off": "rfkill unblock all; sleep 0.5; bluetoothctl power on",
    "bt disconnect": "bluetoothctl disconnect \"$1\" >/dev/null 2>&1 </dev/null; exit 0",
    "bt forget": "bluetoothctl remove \"$1\" >/dev/null 2>&1 </dev/null; exit 0",
    "bt connect": "d=\"$1\"; fail() { m=$(printf '%s\\n' \"$1\" | grep -iE 'fail|error|not available|timeout|rejected|canceled' | tail -n1); [ -n \"$m\" ] || m=\"$2\"; echo \"$m\" >&2; exit 1; }; if ! bluetoothctl info \"$d\" 2>/dev/null </dev/null | grep -qE 'Paired: yes|Bonded: yes'; then o=$(timeout 45 bluetoothctl --agent NoInputNoOutput pair \"$d\" 2>&1 </dev/null); printf '%s\\n' \"$o\" | grep -qi 'Pairing successful' || fail \"$o\" 'Could not pair. Put the device in pairing mode and try again.'; fi; bluetoothctl trust \"$d\" >/dev/null 2>&1 </dev/null; o=$(timeout 25 bluetoothctl connect \"$d\" 2>&1 </dev/null); printf '%s\\n' \"$o\" | grep -qi 'Connection successful' || fail \"$o\" 'Could not connect to the device.'",
}


def run_linux(argv):
    """Linux: run MacShell's original command for this request, untouched."""
    key = " ".join(argv[:3]) if " ".join(argv[:3]) in LINUX else " ".join(argv[:2])
    if argv[:2] == ["wifi", "radio"]:
        return subprocess.call(["nmcli", "radio", "wifi", argv[2]])
    if argv[:2] == ["wifi", "connect"]:
        return subprocess.call(["nmcli", "--wait", "25", "dev", "wifi", "connect", *argv[2:]])
    if argv[:2] == ["conn", "up"] or argv[:2] == ["conn", "down"]:
        return subprocess.call(["nmcli", "connection", argv[1], "id", argv[2]])
    if key in ("bt connect", "bt disconnect", "bt forget"):
        return subprocess.call(["sh", "-c", LINUX[key], "sh", argv[2]])
    if key not in LINUX:
        print(f"macshell-helper: unknown command: {' '.join(argv)}", file=sys.stderr)
        return 64
    return subprocess.call(["sh", "-c", LINUX[key]])


def run(argv, be):
    """Dispatch one request to a structured backend and print MacShell's format."""
    a = argv + ["", "", ""]
    cmd = (a[0], a[1])
    if cmd == ("net", "status"):     sys.stdout.write(fmt_net_status(be.status()))
    elif cmd == ("net", "devices"):  sys.stdout.write(fmt_net_devices(be.conns(), be.status()))
    elif cmd == ("net", "ethernet"): sys.stdout.write(fmt_net_ethernet(be.conns()))
    elif cmd == ("wifi", "radio"):   be.wifi_radio(a[2] == "on")
    elif cmd == ("wifi", "list"):    sys.stdout.write(fmt_wifi_list(be.wifi_list()))
    elif cmd == ("wifi", "connect"):
        pw = argv[4] if len(argv) > 4 and argv[3] == "password" else ""
        be.wifi_connect(argv[2], pw)
    elif cmd == ("wifi", "disconnect"): be.wifi_disconnect()
    elif cmd == ("conn", "list"):    sys.stdout.write(fmt_conn_list(be.conns()))
    elif cmd[0] == "conn" and cmd[1] in ("up", "down"): be.conn(cmd[1] == "up", argv[2])
    elif cmd == ("bt", "status"):    sys.stdout.write(fmt_bt_status(be.bt()))
    elif cmd == ("bt", "power"):     be.bt_power(a[2] == "on")
    elif cmd == ("bt", "scan"):      be.bt_scan()
    elif cmd[0] == "bt" and cmd[1] in ("connect", "disconnect"): be.bt_connect(argv[2], cmd[1] == "connect")
    elif cmd == ("bt", "forget"):    be.bt_forget(argv[2])
    elif cmd[0] == "airplane":       be.airplane(a[1] == "on")
    else:
        raise Fail(f"macshell-helper: unknown command: {' '.join(argv)}", 64)
    return 0


def backend_name():
    b = os.environ.get("MACSHELL_HELPER_BACKEND")
    if b:
        return b
    if os.environ.get("MACSHELL_HELPER_MOCK"):
        return "mock"
    return "windows" if os.name == "nt" else "linux"


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    name = backend_name()
    if argv[:1] == ["apps"]:
        import apps
        return apps.main(argv[1:])
    if argv[:1] == ["about"]:
        import about
        return about.main(argv[1:])
    if argv[:1] == ["theme"]:
        import theme
        return theme.main(argv[1:])
    if argv[:2] == ["wallpaper", "engine"]:
        import wallpaper_engine
        return wallpaper_engine.main(argv[2:])
    if argv[:1] == ["wallpaper"]:
        import wallpaper
        return wallpaper.main(argv[1:])
    if argv[:1] == ["store"]:
        import store
        return store.main(argv[1:], name, os.environ.get("MACSHELL_HELPER_STORE_MOCK")
                          or os.path.join(HERE, "store-mock.json"))
    if name == "linux":
        return run_linux(argv)
    be = WindowsBackend() if name == "windows" else MockBackend(
        os.environ.get("MACSHELL_HELPER_MOCK") or os.path.join(HERE, "mock-state.json"))
    try:
        return run(argv, be)
    except Fail as f:
        print(str(f), file=sys.stderr)
        return f.code or 1


if __name__ == "__main__":
    sys.exit(main())
