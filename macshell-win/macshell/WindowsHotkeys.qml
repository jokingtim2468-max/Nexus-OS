// Global shortcuts on Windows (loaded by shell.qml only on Windows; Hyprland binds these on Linux).
//   Alt+Space    Spotlight              Win+Alt+A   Control Center
//   Win+Alt+N    Wi-Fi / network menu   Win+Alt+F   turn FreeForm off (Windows taskbar comes back)
//   Win (alone)  Launchpad (all apps) instead of the Start menu; Win+<key> shortcuts stay Windows'.
import QtQuick
import Quickshell
import Quickshell.Wayland        // our Windows module (WinHotkey lives there)

Item {
    id: hk
    property var hub: null
    readonly property var bar: hub ? hub.bar : null

    WinStartKey { onPressed: if (hk.bar) hk.bar.spotOpen("apps") }
    WinHotkey { sequence: "Alt+Space"; onPressed: if (hk.bar) hk.bar.search() }
    WinHotkey { sequence: "Win+Alt+A"; onPressed: if (hk.bar) hk.bar.ccRequest(true) }
    WinHotkey { sequence: "Win+Alt+N"; onPressed: if (hk.bar) hk.bar.netRequest(2) }
    WinHotkey {
        sequence: "Win+Alt+F"
        onPressed: {
            var root = Quickshell.env("FREEFORM_ROOT");
            if (root) Quickshell.execDetached(["powershell.exe", "-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
                                               "-File", root + "\\FreeForm.ps1", "-Stop"]);
        }
    }
}
