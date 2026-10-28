pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Hyprland's IPC, answered from Windows: toplevels = open app windows (ToplevelManager, Win32),
// monitors = screens, one workspace per screen (Windows virtual desktops: a later step).
Singleton {
    id: hl
    // Hyprland events (never fire on Windows); declared so MacShell's Connections { onRawEvent } bind
    signal rawEvent(var event)
    readonly property var monitors: QtObject { property var values: hl.monList }
    readonly property var workspaces: QtObject { property var values: hl.wsList }
    readonly property var toplevels: QtObject { property var values: hl.tlList }
    readonly property var focusedMonitor: monList.length > 0 ? monList[0] : null
    readonly property var focusedWorkspace: wsList.length > 0 ? wsList[0] : null

    readonly property var monList: Quickshell.screens.map(function (s, i) {
        return { id: i, name: s.name, x: s.x, y: s.y, width: s.width, height: s.height, focused: i === 0, screen: s,
                 activeWorkspace: { id: i + 1, name: String(i + 1) } };
    })
    readonly property var wsList: monList.map(function (m) { return { id: m.id + 1, name: String(m.id + 1), focused: m.focused, monitor: m }; })
    readonly property var tlList: ToplevelManager.toplevels.values.map(function (t, i) {
        return { address: "0x" + (i + 1).toString(16), title: t.title, wayland: t, activated: t.activated,
                 workspace: wsList.length > 0 ? wsList[0] : null, monitor: focusedMonitor,
                 lastIpcObject: { "class": t.appId, initialClass: t.appId, title: t.title, workspace: { id: 1 } } };
    })

    function monitorFor(screen) {
        for (var i = 0; i < monList.length; i++) if (screen && monList[i].name === screen.name) return monList[i];
        return focusedMonitor;
    }
    function refreshMonitors() {}
    function refreshToplevels() {}
    function refreshWorkspaces() {}
    // MacShell dispatches window rules (float / move / resize) for its own windows; on Windows they are
    // ordinary windows already, so there is nothing to do.
    function dispatch(request) {}
}
