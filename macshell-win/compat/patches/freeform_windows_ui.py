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
    FileView { id: ffDockV3; path: root.configDir + "/ff-dock-v3"; printErrors: false; blockLoading: true }
    function ffDockMigrate() {
        if (Qt.platform.os !== "windows") return;
        if (ffDockV2.text() === "") { iconSize = 40; magnification = 1.5; magnificationEnabled = true; ffDockV2.setText("1"); saveTimer.restart(); }
        // v3: Steam, Chrome, Discord, Spotify and FreeForm Settings; a dot per open window instead of preview cells
        if (ffDockV3.text() === "") { pinned = defaultPinned.slice(); showThumbs = false; spacing = 10; showIndicators = true; ffDockV3.setText("1"); saveTimer.restart(); }
    }'''),
        ('''            if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }''',
         '''            if (ent && root.hub && root.hub.launchOwn && root.hub.launchOwn(ent.id)) ok = true;
            else if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }'''),
        # ── Dock on Windows: slimmer, one dot per open window (no preview cells) ──
        ("""    property int topPad: 8
    property int bottomPad: 9            // room under icons (running dots live here)""",
         """    property int topPad: Qt.platform.os === "windows" ? 5 : 8           // FreeForm: a slimmer Dock on Windows
    property int bottomPad: Qt.platform.os === "windows" ? 7 : 9        // room under icons (running dots live here)"""),
        ("""            if (!running[k]) { running[k] = true; runOrder.push({ key: k, appId: id }); }""",
         """            if (!running[k]) { running[k] = true; runOrder.push({ key: k, appId: id }); }
            wc[k] = (wc[k] || 0) + 1;"""),
        ("""        var running = {};""",
         """        var running = {}, wc = {};"""),
        ("""            list.push({ kind: "app", key: ek, appId: e.id, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true });""",
         """            list.push({ kind: "app", key: ek, appId: e.id, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true, wins: wc[ek] || 0 });"""),
        ("""                        entry: e2, running: true, pinned: false });""",
         """                        entry: e2, running: true, pinned: false, wins: wc[extras[x].key] || 1 });"""),
        ("""                                Rectangle {
                                    visible: !cell.isSep && cell.modelData.running && root.showIndicators
                                    width: 4; height: 4; radius: 2
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.6)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                }""",
         """                                Row {        // one dot per open window (up to 3), like macOS
                                    visible: !cell.isSep && cell.modelData.running && root.showIndicators
                                    spacing: 3
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                    Repeater {
                                        model: Math.max(1, Math.min(3, cell.modelData.wins || 1))
                                        Rectangle { width: 4; height: 4; radius: 2; color: root.dockDark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.6) }
                                    }
                                }"""),
        ("""            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.icon || "") + (it.leaving ? ":L" : ""));""",
         """            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.wins || 0) + ":" + (it.icon || "") + (it.leaving ? ":L" : ""));"""),
        # ── Windows has no compositor blur: the Dock's glass blurs the wallpaper behind it (blur + transparency) ──
        ("""                    Rectangle {
                        visible: !root.liquidActive
                        anchors.fill: parent
                        radius: root.cornerRadius""",
         """                    Item {
                        id: ffBlurSrc
                        anchors.fill: parent
                        visible: false
                        clip: true
                        Image {
                            x: -dock.x
                            y: -(dock.y + win.modelData.height - ui.height)
                            width: win.modelData.width; height: win.modelData.height
                            source: root.wallpaperPath ? "file:///" + String(root.wallpaperPath).replace(/^\\/+/, "") : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 960          // it is blurred anyway: a small copy is plenty
                            asynchronous: true; cache: true
                        }
                    }
                    Rectangle { id: ffBlurMask; anchors.fill: parent; radius: root.cornerRadius; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        visible: false          // off: the wallpaper copy went stale and showed over apps; plain glass instead
                        source: ffBlurSrc
                        blurEnabled: true; blurMax: 48; blur: 1.0
                        saturation: 0.25
                        maskEnabled: true; maskSource: ffBlurMask
                    }
                    Rectangle {
                        visible: !root.liquidActive
                        anchors.fill: parent
                        radius: root.cornerRadius"""),
        # ── Settings on Windows: Windows caption buttons (top right) instead of the Mac dots; acrylic glass ──
        ("""        flags: Qt.Window | Qt.FramelessWindowHint

        // where this window sits on its monitor, for the glass sidebar's backdrop""",
         """        flags: Qt.Window | Qt.FramelessWindowHint
        property int ffBackdrop: Qt.platform.os === "windows" ? 3 : 0     // Windows 11 acrylic blur behind (see init.cpp)
        property bool ffDarkGlass: root.dockDark

        // where this window sits on its monitor, for the glass sidebar's backdrop"""),
        ("""                // traffic lights
                Item {
                    id: lights
                    x: 17; y: 16""",
         """                WinCaption {
                    parent: prefsWindow.contentItem          // the window's own top-right corner
                    visible: Qt.platform.os === "windows"; z: 50
                    window: prefsWindow; dark: root.dockDark
                    anchors.top: parent.top; anchors.right: parent.right; anchors.rightMargin: 1
                }
                // traffic lights
                Item {
                    id: lights
                    visible: Qt.platform.os !== "windows"
                    x: 17; y: 16"""),
        # Settings opens fully on screen, below the menu bar and above the Dock (Windows)
        ("""        prefsWindow.visible = true;
        prefsWindow.requestActivate();
    }""",
         """        if (Qt.platform.os === "windows" && !prefsWindow.visible && Quickshell.screens.length) {
            var sc = Quickshell.screens[0];
            prefsWindow.height = Math.min(prefsWindow.height, sc.height - 124);
            prefsWindow.width = Math.min(prefsWindow.width, sc.width - 40);
            prefsWindow.x = Math.round((sc.width - prefsWindow.width) / 2);
            prefsWindow.y = Math.round(34 + (sc.height - 124 - prefsWindow.height) / 2);
        }
        prefsWindow.visible = true;
        prefsWindow.requestActivate();
    }"""),
        # Settings > Notifications: custom sounds, for all apps or per app (Windows; kept by the Dynamic Island)
        ("""                Row {
                    spacing: 8
                    SButton { t: pal; text: I18n.tr("Send Test Notification");""",
         """                SLabel { visible: !!(root.hub && root.hub.island); t: pal; header: true; text: I18n.tr("Notification Sounds") }
                SCard {
                    id: sndCard
                    visible: !!(root.hub && root.hub.island)
                    t: pal
                    readonly property var isl: root.hub ? root.hub.island : null
                    // apps that have sent notifications, plus any that already have a sound
                    readonly property var apps: {
                        var seen = {}, out = [], m = isl ? isl.sounds : {};
                        for (var k in m) if (k !== "*" && !seen[k]) { seen[k] = 1; out.push(k); }
                        var h = root.bar ? root.bar.notifHist : null;
                        for (var i = 0; h && i < h.count; i++) { var a = h.get(i).app; if (a && !seen[a]) { seen[a] = 1; out.push(a); } }
                        return out.sort();
                    }
                    property string picking: ""
                    function fileName(p) { return p ? String(p).split(/[\\\\/]/).pop() : I18n.tr("Default"); }
                    Process {
                        id: pickProc
                        command: ["macshell-helper", "pickaudio"]
                        stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p !== "" && sndCard.isl) sndCard.isl.setSound(sndCard.picking, p.split(String.fromCharCode(92)).join("/")); } }
                    }
                    function pick(app) { picking = app; pickProc.running = true; }
                    Repeater {
                        model: ["*"].concat(sndCard.apps)
                        delegate: SRow {
                            id: sndRow
                            required property string modelData
                            t: pal
                            title: modelData === "*" ? I18n.tr("All apps") : modelData
                            subtitle: (modelData === "*" ? I18n.tr("Any notification without its own sound: ") : "")
                                      + sndCard.fileName(sndCard.isl ? sndCard.isl.sounds[modelData] : "")
                            Row {
                                spacing: 6
                                SButton { t: pal; text: I18n.tr("Choose\\u2026"); onClicked: sndCard.pick(sndRow.modelData) }
                                SButton { t: pal; text: I18n.tr("Test"); onClicked: if (sndCard.isl) sndCard.isl.testSound(sndRow.modelData) }
                                SButton { t: pal; text: I18n.tr("Reset"); visible: !!(sndCard.isl && sndCard.isl.sounds[sndRow.modelData]); onClicked: sndCard.isl.setSound(sndRow.modelData, "") }
                            }
                        }
                    }
                    // an app that hasn't sent anything yet: type its name
                    SRow {
                        t: pal; title: I18n.tr("Add an app"); subtitle: I18n.tr("Type its name as it appears in notifications, e.g. Discord")
                        Rectangle {
                            width: 180; height: 26; radius: 6; color: pal.field
                            TextInput {
                                id: addApp
                                anchors.fill: parent; anchors.leftMargin: 8; verticalAlignment: TextInput.AlignVCenter
                                color: pal.text; font.family: pal.fam; font.pixelSize: 13; clip: true
                                onAccepted: { if (text.trim() !== "") { sndCard.pick(text.trim()); text = ""; } }
                            }
                        }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: I18n.tr("Send Test Notification");"""),
        # pin / unpin from outside the Dock (Launchpad's right-click menu): saved and shown at once
        ("""    function togglePin(item) {""",
         """    function setPinnedIds(l) { pinned = l; store.setText(JSON.stringify(l, null, 2)); rebuild(); }
    function togglePin(item) {"""),
        # Settings > Widgets: draw every widget in the desktop theme's colours (Widget Studio keeps the setting)
        ("""                    SRow {
                        t: pal
                        title: I18n.tr("Widget size")""",
         """                    SRow {
                        visible: !!(root.hub && root.hub.widgetStudio)
                        t: pal
                        title: I18n.tr("Match the desktop theme")
                        subtitle: I18n.tr("Widgets use the theme's colours; turn off to get each widget's own colours back")
                        SSwitch { t: pal; checked: !!(root.hub && root.hub.widgetStudio && root.hub.widgetStudio.matchTheme)
                                  onToggled: v => { if (root.hub && root.hub.widgetStudio) root.hub.widgetStudio.matchTheme = v; } }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Widget size")"""),
        # Windows: no Liquid Glass (it refracts a saved copy of the wallpaper, which goes stale with Wallpaper
        # Engine or a Windows wallpaper); the plain frosted Dock instead
        ("""    readonly property bool liquidActive: dockStyle === "liquid" && glassState === "ready" && !(bar && bar.gaming)""",
         """    readonly property bool liquidActive: Qt.platform.os !== "windows" && dockStyle === "liquid" && glassState === "ready" && !(bar && bar.gaming)"""),
        # the hovered icon draws above its neighbours, so its name label isn't covered by the next icon
        ("""                                z: isDragged ? 100 : 0""",
         """                                z: isDragged ? 100 : (ma.containsMouse ? 50 : 0)"""),
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
        "ff-steam", "ff-google_chrome", "ff-discord", "ff-spotify", "ff-freeform_settings"
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
                SLabel { t: pal; text: I18n.tr("Taskbar and desktop icon changes apply the next time FreeForm starts. Switch to Windows keeps FreeForm loaded in the background, so opening it again is instant.") }
                SLabel { t: pal; header: true; text: I18n.tr("Theme Spotify and Discord") }
                SCard {
                    t: pal
                    SRow { t: pal; title: I18n.tr("Spotify (installs Spicetify)"); subtitle: I18n.tr("Kept working after Spotify updates, each time FreeForm starts. Needs Spotify from spotify.com, not the Microsoft Store.")
                           SSwitch { t: pal; checked: ffPane.cfg.modSpotify === true; onToggled: v => ffPane.set("modSpotify", v) } }
                    SRow { t: pal; title: I18n.tr("Discord (installs Vencord)"); subtitle: I18n.tr("Re-installed after Discord updates. Client mods are against Discord's Terms of Service; turn this off if that worries you.")
                           SSwitch { t: pal; checked: ffPane.cfg.modDiscord === true; onToggled: v => ffPane.set("modDiscord", v) } }
                }
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
                                ["Win+Alt+A", "Control Center"], ["Win+Alt+N", "Wi-Fi and network"], ["Win+Alt+T", "Show the Windows taskbar"], ["Win+Alt+F", "Switch to Windows and back"]]
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
                    SButton { t: pal; text: I18n.tr("Switch to Windows"); onClicked: if (!(root.hub && root.hub.switchToWindows())) Qt.quit() }
                    SButton { t: pal; text: I18n.tr("Quit FreeForm Completely"); destructive: true; onClicked: Qt.quit() }
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
        # ── Dynamic Island (Windows): notifications show in the island at the top instead of a corner toast ──
        ("""        if ((!root.notifDnd || urg === 2) && !root.notifOpen) {""",
         """        if ((!root.notifDnd || urg === 2) && !root.notifOpen && root.hub && root.hub.island) {
            // a custom sound (Settings > Notifications) replaces the usual chime
            if (root.hub.island.soundFor(rec.app) === "" && root.isSystemNotif(n)) root.playSound("glass", 0.7);
            root.hub.island.notify(rec);
        } else if ((!root.notifDnd || urg === 2) && !root.notifOpen) {"""),
        # the clock keeps its widest width, so it doesn't grow and shrink with each digit (the font has no
        # fixed-width digits on Windows, so "tnum" alone doesn't hold it still)
        ("""                            width: root.barWidgetEnabled("clock") ? clockText.implicitWidth + 16 : 0""",
         """                            property real widest: 0
                            width: root.barWidgetEnabled("clock") ? Math.max(widest, clockText.implicitWidth) + 16 : 0
                            Connections { target: root; function onClockTextChanged() { if (clockText.implicitWidth > clockBtn.widest) clockBtn.widest = clockText.implicitWidth; } }
                            Connections { target: root; function onShowSecondsChanged() { clockBtn.widest = 0; } }"""),
        # Launchpad: right-click an app for Open / Keep in Dock (it used to close Launchpad)
        ("""                                                    MouseArea {
                                                        id: cma
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: { ui.pop = ""; root.launchApp(cell.e); }
                                                    }""",
         """                                                    property bool menu: false
                                                    readonly property var dk: root.hub ? root.hub.dock : null
                                                    readonly property string pid: String(cell.e.id || "").replace(/\\.desktop$/, "")
                                                    readonly property bool pinned: !!(dk && dk.pinned && dk.pinned.indexOf(pid) >= 0)
                                                    MouseArea {
                                                        id: cma
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                        onClicked: mouse => {
                                                            if (mouse.button === Qt.RightButton) { cell.menu = !cell.menu; return; }
                                                            if (cell.menu) { cell.menu = false; return; }
                                                            ui.pop = ""; root.launchApp(cell.e);
                                                        }
                                                    }
                                                    Rectangle {
                                                        visible: cell.menu; z: 20
                                                        anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 14
                                                        width: 170; height: lpMenu.height + 10; radius: 9
                                                        color: panelPal.dark ? "#2C2C2E" : "#FFFFFF"; border.width: 1; border.color: panelPal.sep
                                                        Column {
                                                            id: lpMenu
                                                            x: 5; y: 5; width: parent.width - 10
                                                            Repeater {
                                                                model: [{ t: "Open", f: function () { ui.pop = ""; root.launchApp(cell.e); } },
                                                                        { t: cell.pinned ? "Remove from Dock" : "Keep in Dock", f: function () {
                                                                            if (!cell.dk) return;
                                                                            var l = cell.dk.pinned.slice(), i = l.indexOf(cell.pid);
                                                                            if (i >= 0) l.splice(i, 1); else l.push(cell.pid);
                                                                            cell.dk.setPinnedIds(l); } }]
                                                                delegate: Rectangle {
                                                                    required property var modelData
                                                                    width: lpMenu.width; height: 28; radius: 5
                                                                    color: lpm.containsMouse ? root.accent : "transparent"
                                                                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.modelData.t); color: lpm.containsMouse ? "white" : panelPal.fg; font.family: panelPal.fam; font.pixelSize: 13 }
                                                                    MouseArea { id: lpm; anchors.fill: parent; hoverEnabled: true; onClicked: { cell.menu = false; parent.modelData.f(); } }
                                                                }
                                                            }
                                                        }
                                                    }"""),
        ("""    readonly property bool liquidActive: barStyle === "liquid" && glassState === "ready" && !gaming""",
         """    readonly property bool liquidActive: Qt.platform.os !== "windows" && barStyle === "liquid" && glassState === "ready" && !gaming"""),
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
        if (Qt.platform.os === "windows") { if (!(root.hub && root.hub.switchToWindows())) Qt.quit(); return; }   // FreeForm: back to Windows (stays loaded)
'''),
        ('''            m.push(mc("Log Out\\u2026", function () { root.logOut(); }));''',
         '''            m.push(Qt.platform.os === "windows" ? mi("Switch to Windows", "", function () { root.logOut(); })
                                                : mc("Log Out\\u2026", function () { root.logOut(); }));'''),
    ],
}

if __name__ == "__main__":
    import sys
    from net_bt_windows import apply
    sys.exit(0 if apply(check="--check" in sys.argv, edits_by_file=EDITS) else 1)
