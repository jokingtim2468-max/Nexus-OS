// Global shortcuts on Windows (loaded by shell.qml only on Windows; Hyprland binds these on Linux).
//   Alt+Space    Spotlight              Win+Alt+A   Control Center
//   Win+Alt+N    Wi-Fi / network menu   Win+Alt+F   switch to Windows / back to FreeForm (standby)
//   Win (alone)  Launchpad (all apps) instead of the Start menu; Win+<key> shortcuts stay Windows'.
//   Win+Tab      Mission Control (instead of Task View)
//   Win+Alt+T    show the real Windows taskbar for 15 s (its tray icons: Discord, Steam, ...)
//   Alt+Tab      MacShell's app switcher (Alt+Shift+Tab backwards, Esc cancels)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland        // our Windows module (WinHotkey lives there)

Item {
    id: hk
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    readonly property string stateDir: (Quickshell.env("APPDATA") || "").split(String.fromCharCode(92)).join("/") + "/FreeForm"

    // ── Standby ("Switch to Windows"): FreeForm stays loaded but hidden, so opening it again is instant.
    // The file says 1 while in Windows; FreeForm.ps1 brings the taskbar back then, and opening FreeForm writes 0.
    readonly property bool asleep: standby.active
    function switchToWindows() { standbyFile.setText("1"); standby.active = true; }
    function wake() { standbyFile.setText("0"); standby.active = false; }
    WinStandby { id: standby }
    FileView {
        id: standbyFile
        path: hk.stateDir + "/standby"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: standby.active = text().trim() === "1"
    }
    Component.onCompleted: standbyFile.setText("0")

    WinStartKey {
        enabled: !hk.asleep
        onPressed: if (hk.bar) hk.bar.spotOpen("apps")
        onOverview: if (hk.hub && hk.hub.missionControl) hk.hub.missionControl.toggle()
    }
    WinAltTab {
        enabled: !hk.asleep
        onNext: if (hk.bar) hk.bar.swNext(1)
        onPrev: if (hk.bar) hk.bar.swNext(-1)
        onCommit: if (hk.bar) hk.bar.swCommit()
        onCancel: if (hk.bar) hk.bar.swCancel()
    }
    WinHotkey { sequence: "Alt+Space"; enabled: !hk.asleep; onPressed: if (hk.bar) hk.bar.search() }
    // FreeForm.ps1 shows the taskbar while this file is less than 15 s old
    WinHotkey { sequence: "Win+Alt+T"; onPressed: peekFile.setText(String(Date.now())) }
    FileView { id: peekFile; path: (Quickshell.env("APPDATA") || "").split(String.fromCharCode(92)).join("/") + "/FreeForm/peek-taskbar"; printErrors: false }
    WinHotkey { sequence: "Win+Alt+A"; enabled: !hk.asleep; onPressed: if (hk.bar) hk.bar.ccRequest(true) }
    WinHotkey { sequence: "Win+Alt+N"; enabled: !hk.asleep; onPressed: if (hk.bar) hk.bar.netRequest(2) }
    WinHotkey {
        sequence: "Win+Alt+F"
        onPressed: if (hk.asleep) hk.wake(); else hk.switchToWindows()
    }
}
