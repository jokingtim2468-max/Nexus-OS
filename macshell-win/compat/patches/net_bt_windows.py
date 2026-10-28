"""Patch: run MacShell's network / Bluetooth UI on Windows.

Applied to our copy (macshell-win/macshell/). Every edit is an exact find -> replace that
must match exactly once, so upstream changes are caught instead of silently mis-patched.

1. Every nmcli / bluetoothctl / rfkill call -> `macshell-helper ...`, which prints the same
   text MacShell already parses (compat/helper/macshell_helper.py). UI + parsing untouched.
2. The wired-network symbol is an Ethernet cable (RJ45 plug + cord), not Apple's <···>, and it
   shows whenever Ethernet is connected, like Windows (which routes over the cable when both
   are up); MacShell showed it only when Wi-Fi was off.
3. Ethernet rows in the Wi-Fi menu use that symbol (they showed the Wi-Fi fan).
4. The Wi-Fi menu gets a Bluetooth on/off row under its header, built from MacShell's own
   PSwitch / Glyph / palette, calling MacShell's own root.toggleBt().
5. `qs ipc call network toggle|open|close` opens that menu, in the same pattern as MacShell's
   `controlcenter` IPC (for a Win+A style hotkey, and for automated tests).

    python compat/patches/net_bt_windows.py          # apply (idempotent)
    python compat/patches/net_bt_windows.py --check  # verify it is applied
"""
import os
import sys

BLOCK = "BLOCK"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "macshell")

EDITS = {
    "MacBar.qml": [
        # ── Wi-Fi / Ethernet status ──
        ('command: ["sh", "-c", "nmcli radio wifi 2>/dev/null; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep \'^yes\' | head -n1; echo; nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q \'^ethernet:connected$\' && echo eth || echo -"]',
         'command: ["macshell-helper", "net", "status"]'),
        ('Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"]);',
         'Quickshell.execDetached(["macshell-helper", "wifi", "radio", root.wifiOn ? "on" : "off"]);'),
        # ── Wi-Fi network list ──
        ('''        command: ["sh", "-c",
            "nmcli dev wifi rescan >/dev/null 2>&1; "
            + "nmcli -t -f NAME,TYPE connection show 2>/dev/null | sed -n 's/:802-11-wireless$//p' | sed 's/^/S:/'; "
            + "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null | sed 's/^/N:/'"]''',
         '''        command: ["macshell-helper", "wifi", "list"]'''),
        # ── join / leave ──
        ('var cmd = ["nmcli", "--wait", "25", "dev", "wifi", "connect", ssid];',
         'var cmd = ["macshell-helper", "wifi", "connect", ssid];'),
        ('''sh("nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | cut -d: -f1 | head -n1 | xargs -r nmcli dev disconnect");''',
         '''Quickshell.execDetached(["macshell-helper", "wifi", "disconnect"]);'''),
        # ── Ethernet & VPN ──
        ('command: ["sh", "-c", "nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null"]',
         'command: ["macshell-helper", "conn", "list"]'),
        ('var args = c.active ? ["nmcli", "connection", "down", "id", c.name] : ["nmcli", "connection", "up", "id", c.name];',
         'var args = ["macshell-helper", "conn", c.active ? "down" : "up", c.name];'),
        # ── Bluetooth ──
        # block edit: (BLOCK, start marker, end marker inclusive, replacement)
        (BLOCK, '        command: ["sh", "-c",\n            "p=$(timeout 4 bluetoothctl show', '"done"\n        ]',
         '        command: ["macshell-helper", "bt", "status"]'),
        ('command: ["sh", "-c", "bluetoothctl --timeout 10 scan on >/dev/null 2>&1 </dev/null; exit 0"]',
         'command: ["macshell-helper", "bt", "scan"]'),
        ('btActionProc.command = ["sh", "-c", "bluetoothctl disconnect \\"$1\\" >/dev/null 2>&1 </dev/null; exit 0", "sh", mac];',
         'btActionProc.command = ["macshell-helper", "bt", "disconnect", mac];'),
        (BLOCK, '            btActionProc.command = ["sh", "-c",\n                "d=\\"$1\\"; "', '"sh", mac];',
         '            btActionProc.command = ["macshell-helper", "bt", "connect", mac];'),
        ('''        Quickshell.execDetached(["sh", "-c",
            root.btOn ? "rfkill unblock bluetooth 2>/dev/null; sleep 0.3; bluetoothctl power on"
                      : "bluetoothctl power off"]);''',
         '''        Quickshell.execDetached(["macshell-helper", "bt", "power", root.btOn ? "on" : "off"]);'''),
        ('sh(airplane ? "rfkill unblock all; sleep 0.5; bluetoothctl power on" : "rfkill block all");',
         'Quickshell.execDetached(["macshell-helper", "airplane", airplane ? "off" : "on"]);'),
        # ── IPC: open the Wi-Fi / network menu (same pattern as the controlcenter target) ──
        ('''        function close(): void { root.ccRequest(false); }
    }''',
         '''        function close(): void { root.ccRequest(false); }
    }
    // qs -c MacShell ipc call network toggle | open | close   (the Wi-Fi / Ethernet / Bluetooth menu)
    signal netRequest(int mode)                 // 0 close, 1 open, 2 toggle
    IpcHandler {
        target: "network"
        function toggle(): void { root.netRequest(2); }
        function open(): void { root.netRequest(1); }
        function close(): void { root.netRequest(0); }
    }'''),
        ('''                    function onCcRequest(open) {
                        if (!ui.toastScreen || !root.ccEnabled) return;
                        ui.pop = (open && ui.pop !== "cc") ? "cc" : "";
                    }
                }''',
         '''                    function onCcRequest(open) {
                        if (!ui.toastScreen || !root.ccEnabled) return;
                        ui.pop = (open && ui.pop !== "cc") ? "cc" : "";
                    }
                    function onNetRequest(mode) {
                        if (!ui.toastScreen) return;
                        if (mode === 0 || (mode === 2 && ui.pop === "wifi")) ui.pop = "";
                        else if (ui.pop !== "wifi") ui.openPop("wifi", wifiBtn.mapToItem(ui, 0, 0).x);
                    }
                }'''),
        # ── Windows rule: wired connection -> Ethernet icon, even when Wi-Fi is also joined ──
        ('readonly property bool showEthernet: ethernetUp && wifiSsid === ""',
         'readonly property bool showEthernet: ethernetUp                 // Windows: the cable wins when both are up'),
        # ── Ethernet symbol: a cable (RJ45 plug + cord) instead of Apple's <···> ──
        ('''            } else if (k === "ethernet") {
                // Apple's Ethernet symbol: <···>
                poly([5.2, 4.6, 1.6, 9, 5.2, 13.4], false);
                poly([12.8, 4.6, 16.4, 9, 12.8, 13.4], false);
                circ(6.5, 9, 1.1); ctx.fill();
                circ(9, 9, 1.1); ctx.fill();
                circ(11.5, 9, 1.1); ctx.fill();''',
         '''            } else if (k === "ethernet") {
                // Ethernet cable: RJ45 plug (body, latch, contacts) with its cord running down
                rrect(4.2, 1.6, 9.6, 8.6, 1.4); ctx.stroke();          // plug body
                line(7, 1.6, 7, 3.6); line(9, 1.6, 9, 3.6); line(11, 1.6, 11, 3.6);   // contacts
                rrect(6.6, 10.2, 4.8, 2.4, 0.6); ctx.fill();            // boot / strain relief
                ctx.beginPath(); ctx.moveTo(9, 12.6);                   // cord
                ctx.bezierCurveTo(9, 15.4, 13.6, 14.2, 13.8, 16.8); ctx.stroke();'''),
        # ── Ethernet rows in the Wi-Fi menu: the cable symbol, not the Wi-Fi fan ──
        ('kind:modelData.type==="vpn"?"lock":"wifi"; color:pp.fg }',
         'kind:modelData.type==="vpn"?"lock":"ethernet"; color:pp.fg }'),
        # ── Bluetooth on/off inside the Wi-Fi menu (same row style as the Wi-Fi header) ──
        ('''                                checked: root.wifiOn
                                onToggled: { root.toggleWifi(); wifiAfter.restart(); }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: pp.sep }''',
         '''                                checked: root.wifiOn
                                onToggled: { root.toggleWifi(); wifiAfter.restart(); }
                            }
                        }
                        // Bluetooth on/off, so both radios can be switched from this menu
                        Item {
                            visible: !wifiCol.showBack      // the popover only; the Control Center has its own tile
                            width: parent.width; height: visible ? 30 : 0
                            Glyph { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; kind: "bluetooth"; color: root.btOn ? pp.fg : pp.fg2 }
                            Text {
                                x: 30; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Bluetooth") + (root.btConnectedName !== "" ? " \\u00b7 " + root.btConnectedName : "")
                                color: pp.fg
                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                            }
                            PSwitch {
                                t: pp
                                anchors.right: parent.right; anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                checked: root.btOn
                                onToggled: root.toggleBt()
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: pp.sep }'''),
    ],
    "MacDock.qml": [
        # Settings > Wi-Fi: Ethernet details
        ('''command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$2==\\"ethernet\\"' | head -1 | while IFS=: read -r d t st c; do ip=$(ip -4 -o addr show \\"$d\\" 2>/dev/null | awk '{print $4}' | head -1); sp=$(cat /sys/class/net/$d/speed 2>/dev/null); printf '%s\\t%s\\t%s\\t%s\\t%s' \\"$d\\" \\"$st\\" \\"$c\\" \\"$ip\\" \\"$sp\\"; done"]''',
         '''command: ["macshell-helper", "net", "ethernet"]'''),
        # Settings > Network: interface list
        ('''command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | grep -vE ':(loopback|wifi-p2p|bridge):' | while IFS=: read -r d t s c; do ip=$(ip -4 -o addr show \\"$d\\" 2>/dev/null | awk '{print $4}' | head -1); printf '%s\\\\t%s\\\\t%s\\\\t%s\\\\t%s\\\\n' \\"$d\\" \\"$t\\" \\"$s\\" \\"$c\\" \\"$ip\\"; done"]''',
         '''command: ["macshell-helper", "net", "devices"]'''),
    ],
}


def apply(check=False):
    ok = True
    for fname, edits in EDITS.items():
        path = os.path.join(ROOT, fname)
        text = open(path, encoding="utf-8").read()
        new = text
        for i, edit in enumerate(edits):
            if edit[0] == BLOCK:                           # resolve start..end to the literal text
                _, start, end, rep = edit
                a = new.find(start)
                if a < 0:
                    if rep in new:
                        continue                           # already applied
                    print(f"{fname} edit {i}: start marker not found"); ok = False; continue
                b = new.find(end, a)
                old = new[a:b + len(end)]
            else:
                old, rep = edit
            if rep in new:
                continue                                   # already applied
            n = new.count(old)
            if n != 1:
                print(f"{fname} edit {i}: expected 1 match, found {n}")
                ok = False
                continue
            if check:
                print(f"{fname} edit {i}: NOT applied")
                ok = False
                continue
            new = new.replace(old, rep)
        if not check and new != text:
            open(path, "w", encoding="utf-8").write(new)
            print(f"patched {fname}")
    return ok


if __name__ == "__main__":
    sys.exit(0 if apply(check="--check" in sys.argv) else 1)
