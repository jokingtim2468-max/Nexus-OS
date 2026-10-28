"""Patch: make MacShell's menu bar behave on Windows.

Applied after freeform_apps.py (same engine: exact find -> replace, each must match once).

1. The menu bar tucks away while an app window is focused and slides back when the pointer
   touches the top edge of the screen (or a menu is open). On Windows it no longer reserves
   space, so apps use the whole screen, like a macOS full-screen app.
2. No workspace numbers: Windows has no Hyprland workspaces to switch.
4. Dock: Windows apps pinned by default (ids are the ff-*.desktop files `apps sync` writes).
3. Power: Restart / Shut Down use Windows' shutdown.exe, Sleep suspends, and "Log Out" becomes
   "Quit FreeForm" (the launcher then brings the taskbar back).

    python compat/patches/apply_all.py
"""
EDITS = {
    "MacDock.qml": [
        ('''            if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }''',
         '''            if (ent && root.hub && root.hub.launchOwn && root.hub.launchOwn(ent.id)) ok = true;
            else if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }'''),
        # ── 4. Windows apps pinned by default ──
        ('''    readonly property var defaultPinned: [
        "org.gnome.Nautilus",''',
         '''    readonly property var defaultPinned: Qt.platform.os === "windows" ? [
        "ff-freeform_finder", "ff-microsoft_edge", "ff-google_chrome", "ff-firefox", "ff-terminal",
        "ff-visual_studio_code", "ff-discord", "ff-spotify", "ff-steam",
        "ff-freeform_music", "ff-freeform_widget_studio", "ff-freeform_app_store", "ff-freeform_settings"
    ] : [
        "org.gnome.Nautilus",'''),
    ],
    "MacBar.qml": [
        # ── FreeForm's own apps open in-process (hub.launchOwn), not through a second qs.exe ──
        ('''        saveTimer.restart();
        e.execute();
    }''',
         '''        saveTimer.restart();
        if (root.hub && root.hub.launchOwn && root.hub.launchOwn(e.id)) return;
        e.execute();
    }'''),
        ('''        var e = lookup(activeAppId);
        if (e) e.execute();''',
         '''        var e = lookup(activeAppId);
        if (e && root.hub && root.hub.launchOwn && root.hub.launchOwn(e.id)) return;
        if (e) e.execute();'''),
        # ── 1. auto-hide state ──
        ('''    property bool barEnabled: true           // the menu bar strip itself''',
         '''    property bool barEnabled: true           // the menu bar strip itself
    // FreeForm (Windows): the bar tucks away while an app window is focused; touching the top edge brings it back
    readonly property bool barAutoHide: Qt.platform.os === "windows"
    property bool barPeek: false
    readonly property bool barAppFocused: barAutoHide && ToplevelManager.activeToplevel !== null
    Timer { id: barUnpeek; interval: 600; onTriggered: root.barPeek = false }'''),
        ('''            exclusiveZone: root.barEnabled ? root.barHeight : 0''',
         '''            exclusiveZone: root.barEnabled && !root.barAutoHide ? root.barHeight : 0'''),
        ('''            Item {
                id: ui
                anchors.fill: parent
''',
         '''            Item {
                id: ui
                anchors.fill: parent
                // FreeForm: slid up out of sight while an app is focused (menus open keep it down)
                readonly property bool tucked: root.barAppFocused && !root.barPeek && pop === ""
                property real tuckShift: tucked ? root.barHeight + 6 : 0
                Behavior on tuckShift { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                transform: Translate { y: -ui.tuckShift }
                HoverHandler {
                    enabled: root.barAutoHide
                    onHoveredChanged: if (hovered) { barUnpeek.stop(); root.barPeek = true; } else barUnpeek.restart()
                }
'''),
        # notifications stay where they are while the bar is tucked
        ('''                    id: toastMask
                    x: toastArea.x; y: toastArea.y
''',
         '''                    id: toastMask
                    x: toastArea.x; y: toastArea.y
                    transform: Translate { y: ui.tuckShift }
'''),
        ('''                    id: toastArea
                    z: 12
''',
         '''                    id: toastArea
                    z: 12
                    transform: Translate { y: ui.tuckShift }
'''),
        ('''            visible: root.barBgOpacity > 0.001
''',
         '''            visible: root.barBgOpacity > 0.001 && ui.tuckShift < 1
'''),
        # a 2 px strip at the top edge that brings the tucked bar back
        ('''        PanelWindow {
            id: win
''',
         '''        PanelWindow {
            screen: perScreen.modelData
            visible: root.barAppFocused
            anchors { left: true; right: true; top: true }
            implicitHeight: 2
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "macbarpeek"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            HoverHandler { onHoveredChanged: if (hovered) { barUnpeek.stop(); root.barPeek = true; } }
        }

        PanelWindow {
            id: win
'''),
        # ── 2. no workspace numbers on Windows ──
        ('''    readonly property var wsIds: {
        var ids = [], vals = Hyprland.workspaces.values;''',
         '''    readonly property var wsIds: {
        if (Qt.platform.os === "windows") return [];
        var ids = [], vals = Hyprland.workspaces.values;'''),
        # ── Alt+Tab (WinAltTab in WindowsHotkeys.qml): focus the picked window directly ──
        ('''        root.swOpen = false;
        if (!a || !a.win) return;
''',
         '''        root.swOpen = false;
        if (!a || !a.win) return;
        if (Qt.platform.os === "windows") { try { a.win.activate(); } catch (e0) {} return; }
'''),
        # ── 3. power ──
        ('''    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }''',
         '''    function sh(cmd) {
        if (Qt.platform.os === "windows") {                                  // FreeForm: Windows' own power commands
            if (cmd === "systemctl reboot") Quickshell.execDetached(["shutdown.exe", "/r", "/t", "0"]);
            else if (cmd === "systemctl poweroff") Quickshell.execDetached(["shutdown.exe", "/s", "/t", "0"]);
            return;
        }
        Quickshell.execDetached(["sh", "-c", cmd]);
    }'''),
        # Windows' own lock screen: it runs on the secure desktop, which nothing (FreeForm included) can draw over
        ('''    function lockScreen() {
''',
         '''    function lockScreen() {
        if (Qt.platform.os === "windows") { Quickshell.execDetached(["rundll32.exe", "user32.dll,LockWorkStation"]); return; }
'''),
        ('''    function sleepMachine() {
''',
         '''    function sleepMachine() {
        if (Qt.platform.os === "windows") { Quickshell.execDetached(["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"]); return; }
'''),
        ('''    function logOut() {
''',
         '''    function logOut() {
        if (Qt.platform.os === "windows") { Qt.quit(); return; }            // FreeForm: back to the Windows desktop
'''),
        ('''            m.push(mc("Log Out\\u2026", function () { root.logOut(); }));''',
         '''            m.push(Qt.platform.os === "windows" ? mi("Quit FreeForm", "", function () { Qt.quit(); })
                                                : mc("Log Out\\u2026", function () { root.logOut(); }));'''),
    ],
}

if __name__ == "__main__":
    import sys
    from net_bt_windows import apply
    sys.exit(0 if apply(check="--check" in sys.argv, edits_by_file=EDITS) else 1)
