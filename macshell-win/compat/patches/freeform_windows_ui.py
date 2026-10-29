"""Patch: make MacShell's menu bar behave on Windows.

Applied after freeform_apps.py (same engine: exact find -> replace, each must match once).

1. The menu bar tucks away while a full-screen app (game, video) is in front and slides back
   when the pointer touches the top edge (or a menu is open). Otherwise it stays, and windows
   are kept below it.
2. No workspace numbers: Windows has no Hyprland workspaces to switch.
4. Dock: Windows apps pinned by default (ids are the ff-*.desktop files `apps sync` writes).
3. Power: Restart / Shut Down use Windows' shutdown.exe, Sleep suspends, and "Log Out" becomes
   "Quit FreeForm" (the launcher then brings the taskbar back).

    python compat/patches/apply_all.py
"""
EDITS = {
    "MacDock.qml": [
        # ── Dock on Windows: taskbar-sized, 1.5x magnification of the hovered icon and its neighbours ──
        ('''    readonly property real magRadius: (iconSize + spacing) * 2.6''',
         '''    readonly property real magRadius: (iconSize + spacing) * (Qt.platform.os === "windows" ? 1.6 : 2.6)'''),
        ('''    readonly property int windowHeight: Math.ceil(margin + bgHeight + iconSize * (effMag - 1) + 72 + menuRoom)''',
         '''    readonly property int windowHeight: Math.ceil(margin + bgHeight + iconSize * (effMag - 1) + (Qt.platform.os === "windows" ? 104 : 72) + menuRoom)'''),
        ('''        onLoaded: {
            try { root.applySettings(JSON.parse(text())); } catch (err) { }
            root.settingsReady = true;''',
         '''        onLoaded: {
            try { root.applySettings(JSON.parse(text())); } catch (err) { }
            root.ffDockMigrate();
            root.settingsReady = true;'''),
        ('''        onLoadFailed: root.settingsReady = true
    }
    Timer { id: saveTimer; interval: 400; onTriggered: root.saveSettings() }''',
         '''        onLoadFailed: { root.ffDockMigrate(); root.settingsReady = true; }
    }
    Timer { id: saveTimer; interval: 400; onTriggered: root.saveSettings() }
    // FreeForm (Windows), once: a Dock the size of the Windows taskbar with gentle magnification
    FileView { id: ffDockV2; path: root.configDir + "/ff-dock-v2"; printErrors: false; blockLoading: true }
    function ffDockMigrate() {
        if (Qt.platform.os !== "windows" || ffDockV2.text() !== "") return;
        iconSize = 40; magnification = 1.5; magnificationEnabled = true;
        ffDockV2.setText("1"); saveTimer.restart();
    }'''),
        ('''            if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }''',
         '''            if (ent && root.hub && root.hub.launchOwn && root.hub.launchOwn(ent.id)) ok = true;
            else if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }'''),
        # ── Trash = the Windows Recycle Bin ──
        ('''        if (item.special === "trash") {
            // the file manager first''',
         '''        if (item.special === "trash") {
            if (Qt.platform.os === "windows") { Quickshell.execDetached(["explorer.exe", "shell:RecycleBinFolder"]); return; }
            // the file manager first'''),
        ('''    function emptyTrash() {
''',
         '''    function emptyTrash() {
        if (Qt.platform.os === "windows") {
            Quickshell.execDetached(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"]);
            if (bar) bar.playSound("trash", 0.8);
            return;
        }
'''),
        # ── 4. Windows apps pinned by default ──
        ('''    readonly property var defaultPinned: [
        "org.gnome.Nautilus",''',
         '''    readonly property var defaultPinned: Qt.platform.os === "windows" ? [
        "ff-file_explorer", "ff-microsoft_edge", "ff-google_chrome", "ff-firefox", "ff-terminal",
        "ff-visual_studio_code", "ff-discord", "ff-spotify", "ff-steam",
        "ff-freeform_widget_studio", "ff-freeform_settings"
    ] : [
        "org.gnome.Nautilus",'''),
        # ── Settings: FreeForm's own tab and a Windows tab (Windows only) ──
        ("""            { id: "about",      sec: 7, name: "About",           glyph: "about",    c1: "#A7A7AD", c2: "#7C7C82", keys: "version reset config folder macdock macbar macshell" }
        ]""",
         """            { id: "about",      sec: 7, name: "About",           glyph: "about",    c1: "#A7A7AD", c2: "#7C7C82", keys: "version reset config folder macdock macbar macshell" }
        ].concat(Qt.platform.os === "windows" ? [
            // 8 · FreeForm on Windows
            { id: "freeform",   sec: 8, name: "FreeForm",        glyph: "behavior", c1: "#3A3A3C", c2: "#000000", keys: "freeform startup sign in login launcher taskbar desktop icons update version quit exit shortcuts hotkeys" },
            { id: "windows",    sec: 8, name: "Windows",         wg: "keyboard",   c1: "#3D9BFF", c2: "#0A6CFF", keys: "windows update apps default storage privacy accounts time language gaming printers night light control panel device manager" }
        ] : [])"""),
        ("""                        apps: paneApps, about: paneAbout
                    })""",
         """                        apps: paneApps, about: paneAbout, freeform: paneFreeForm, windows: paneWindows
                    })"""),
        ("""        Component {
            id: paneAbout
""",
         """        // ── FreeForm (Windows): the launcher's options, updates, shortcuts ──
        Component {
            id: paneFreeForm
            Column {
                id: ffPane
                spacing: 10
                property var cfg: ({})
                function set(k, v) { var c = Object.assign({}, cfg); c[k] = v; cfg = c; Quickshell.execDetached(["macshell-helper", "ffconfig", "set", k, v ? "1" : "0"]); }
                Process { running: true; command: ["macshell-helper", "ffconfig", "get"]; stdout: StdioCollector { onStreamFinished: { try { ffPane.cfg = JSON.parse(text); } catch (e) {} } } }
                SLabel { t: pal; header: true; text: I18n.tr("Startup") }
                SCard {
                    t: pal
                    SRow { t: pal; title: I18n.tr("Start FreeForm when I sign in"); SSwitch { t: pal; checked: !!ffPane.cfg.autoStart; onToggled: v => ffPane.set("autoStart", v) } }
                    SRow { t: pal; title: I18n.tr("Skip the launcher window"); subtitle: I18n.tr("Hold Shift while opening FreeForm to see it anyway"); SSwitch { t: pal; checked: !!ffPane.cfg.skipLauncher; onToggled: v => ffPane.set("skipLauncher", v) } }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Windows") }
                SCard {
                    t: pal
                    SRow { t: pal; title: I18n.tr("Hide the Windows taskbar"); subtitle: I18n.tr("Win+Alt+T shows it for a moment"); SSwitch { t: pal; checked: ffPane.cfg.hideTaskbar !== false; onToggled: v => ffPane.set("hideTaskbar", v) } }
                    SRow { t: pal; title: I18n.tr("Hide Windows desktop icons"); SSwitch { t: pal; checked: ffPane.cfg.hideIcons !== false; onToggled: v => ffPane.set("hideIcons", v) } }
                }
                SLabel { t: pal; text: I18n.tr("Taskbar and desktop icon changes apply the next time FreeForm starts.") }
                SLabel { t: pal; header: true; text: I18n.tr("Updates") }
                SCard {
                    t: pal
                    SRow { t: pal; title: I18n.tr("Install updates automatically"); SSwitch { t: pal; checked: ffPane.cfg.autoUpdate !== false; onToggled: v => ffPane.set("autoUpdate", v) } }
                    SRow {
                        t: pal; title: I18n.tr("Version"); subtitle: ffPane.cfg.version || ""
                        SButton { t: pal; text: I18n.tr("Check for Updates…"); onClicked: if (ffPane.cfg.root) Quickshell.execDetached(["cmd.exe", "/c", "start", "", ffPane.cfg.root + "\\\\FreeFormLauncher.cmd"]) }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Keyboard Shortcuts") }
                SCard {
                    t: pal
                    Repeater {
                        model: [["Win", "Launchpad (all apps)"], ["Alt+Space", "Spotlight search"], ["Win+Tab", "Mission Control"], ["Alt+Tab", "Switch between apps"],
                                ["Win+Alt+A", "Control Center"], ["Win+Alt+N", "Wi-Fi and network"], ["Win+Alt+T", "Show the Windows taskbar"], ["Win+Alt+F", "Turn FreeForm off"]]
                        delegate: SRow {
                            required property var modelData
                            t: pal; title: I18n.tr(modelData[1])
                            Text { text: modelData[0]; color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13 }
                        }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: I18n.tr("Open Launcher…"); onClicked: if (ffPane.cfg.root) Quickshell.execDetached(["cmd.exe", "/c", "start", "", ffPane.cfg.root + "\\\\FreeFormLauncher.cmd"]) }
                    SButton { t: pal; text: I18n.tr("Quit FreeForm"); destructive: true; onClicked: Qt.quit() }
                }
            }
        }

        // ── Windows: shortcuts into Windows' own settings ──
        Component {
            id: paneWindows
            Column {
                spacing: 10
                Repeater {
                    model: [
                        { h: "System", rows: [["Windows Update", "ms-settings:windowsupdate"], ["Storage", "ms-settings:storagesense"], ["Night light", "ms-settings:nightlight"],
                                              ["Display resolution and scale", "ms-settings:display"], ["Power and sleep", "ms-settings:powersleep"]] },
                        { h: "Apps", rows: [["Installed apps", "ms-settings:appsfeatures"], ["Default apps", "ms-settings:defaultapps"], ["Startup apps", "ms-settings:startupapps"],
                                            ["App volume and devices", "ms-settings:apps-volume"]] },
                        { h: "Devices", rows: [["Printers and scanners", "ms-settings:printers"], ["Mouse", "ms-settings:mousetouchpad"], ["Typing and keyboard layouts", "ms-settings:regionlanguage"]] },
                        { h: "Accounts and Privacy", rows: [["Your info", "ms-settings:yourinfo"], ["Sign-in options", "ms-settings:signinoptions"], ["Privacy and security", "ms-settings:privacy"]] },
                        { h: "More", rows: [["Date and time", "ms-settings:dateandtime"], ["Gaming", "ms-settings:gaming-gamemode"], ["Windows Settings", "ms-settings:"],
                                            ["Control Panel", "control.exe"], ["Device Manager", "devmgmt.msc"]] }
                    ]
                    delegate: Column {
                        id: winGroup
                        required property var modelData
                        width: parent.width
                        spacing: 10
                        SLabel { t: pal; header: true; text: I18n.tr(winGroup.modelData.h) }
                        SCard {
                            t: pal
                            Repeater {
                                model: winGroup.modelData.rows
                                delegate: SRow {
                                    required property var modelData
                                    t: pal; title: I18n.tr(modelData[0])
                                    SButton {
                                        t: pal; text: I18n.tr("Open")
                                        onClicked: Quickshell.execDetached(modelData[1].indexOf("ms-settings:") === 0 ? ["explorer.exe", modelData[1]] : (modelData[1] === "devmgmt.msc" ? ["mmc.exe", "devmgmt.msc"] : [modelData[1]]))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: paneAbout
"""),
        # ── Settings on Windows: account name, profile picture ──
        ('''        command: ["sh", "-c", "n=$(getent passwd \\"$USER\\" | cut -d: -f5 | cut -d, -f1); printf '%s' \\"${n:-$USER}\\""]''',
         '''        command: Qt.platform.os === "windows" ? ["cmd.exe", "/c", "echo %USERNAME%"]
                 : ["sh", "-c", "n=$(getent passwd \\"$USER\\" | cut -d: -f5 | cut -d, -f1); printf '%s' \\"${n:-$USER}\\""]'''),
        ('''                    command: ["sh", "-c", "f=$(zenity''',
         '''                    command: Qt.platform.os === "windows" ? ["macshell-helper", "pickface"] : ["sh", "-c", "f=$(zenity'''),
    ],
    "MacBar.qml": [
        # ── Control Center on Windows: brightness (laptop panel or DDC/CI monitor), output/input device ──
        # brightness on Windows: one long-running brightness.ps1 takes every slider value as it moves
        ('''    function refreshBrightness() { if (!brightProc.running) brightProc.running = true; }''',
         '''    function refreshBrightness() { if (Qt.platform.os !== "windows" && !brightProc.running) brightProc.running = true; }
    Process {
        id: brightServe
        running: Qt.platform.os === "windows" && (Quickshell.env("FREEFORM_HELPER") || "") !== ""
        stdinEnabled: true
        command: ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                  Quickshell.env("FREEFORM_HELPER") + "/brightness.ps1", "serve"]
        stdout: SplitParser {
            onRead: line => {
                var p = parseInt(line);
                if (!isNaN(p) && !brightApply.running && Math.abs(p / 100 - root.brightness) > 0.015) root.brightness = p / 100;
            }
        }
    }'''),
        ('''        id: brightApply
        interval: 40
        onTriggered: Quickshell.execDetached(["brightnessctl"''',
         '''        id: brightApply
        interval: Qt.platform.os === "windows" ? 16 : 40
        onTriggered: if (Qt.platform.os === "windows") brightServe.write(Math.max(1, Math.round(root.brightness * 100)) + "\\n"); else Quickshell.execDetached(["brightnessctl"'''),
        ('''        osdQuiet("volume", 1500);
        Quickshell.execDetached(["sh", "-c", "wpctl set-default''',
         '''        osdQuiet("volume", 1500);
        if (Qt.platform.os === "windows") { Pipewire.setDefault(n); return; }
        Quickshell.execDetached(["sh", "-c", "wpctl set-default'''),
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
    // FreeForm (Windows): the bar tucks away while a full-screen app is in front; touching the top edge brings it back
    readonly property bool barAutoHide: Qt.platform.os === "windows"
    property bool barPeek: false
    readonly property bool barAppFocused: barAutoHide && ToplevelManager.activeToplevel !== null && ToplevelManager.activeToplevel.fullscreen
    Timer { id: barUnpeek; interval: 600; onTriggered: root.barPeek = false }'''),
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
