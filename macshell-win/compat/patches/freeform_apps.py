"""Patch: hook FreeForm's own apps into MacShell's menus.

Applied after net_bt_windows.py (same engine: exact find -> replace, each must match once).

1. Apple menu: "App Store..." and "Welcome Tour..." under System Settings (AppStore.qml, Tutorial.qml).
2. Wallpaper Engine: Settings > Wallpaper lists your Steam Workshop wallpapers (animated
   previews); clicking one plays it through Wallpaper Engine, and the Liquid Glass refracts its
   preview. Picking a normal wallpaper afterwards closes Wallpaper Engine's. Not installed ->
   a "View on Steam" row (it's a paid Steam app; we only link to the store page).
4. FreeForm branding: the FF mark (ff-logo-*.svg) instead of the Apple logo in the menu bar and
   Settings, the FF app icon (assets/freeform-logo.png) for MacShell's own windows, and
   "About This PC" showing FreeForm (on Windows its specs come from `macshell-helper about`).
3. Theme presets (Settings > Appearance > Theme): Black, White, Graphite, Default. Each sets
   MacShell's appearance, accent and glass, and runs `macshell-helper theme apply` for Windows
   app mode and Spotify (via Spicetify, when installed). Colours: compat/helper/theme.py.

    python compat/patches/freeform_apps.py          # apply (idempotent)
    python compat/patches/freeform_apps.py --check  # verify it is applied
"""
import sys

from net_bt_windows import apply

EDITS = {
    "MacBar.qml": [
        ('''            m.push(mi("System Settings\\u2026", "", function () { root.openSettings(); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { root.lockScreen(); }));''',
         '''            m.push(mi("System Settings\\u2026", "", function () { root.openSettings(); }));
            m.push(mi("App Store\\u2026", "", function () { if (hub && hub.appStore) hub.appStore.open(""); }));
            m.push(mi("Welcome Tour\\u2026", "", function () { if (hub && hub.tour) hub.tour.start(); }));
            m.push(mi("Widget Studio\\u2026", "", function () { if (hub && hub.widgetStudio) hub.widgetStudio.open(); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { root.lockScreen(); }));'''),
        # ── Wallpaper Engine state + apply ──
        ('''    function wpApply(path) {
        var pair = wpPairOf(path);''',
         '''    // ── Wallpaper Engine (FreeForm): Steam Workshop wallpapers, see compat/helper/wallpaper_engine.py ──
    property bool weInstalled: false
    property var weItems: []                 // { id, title, type, preview, file }
    property string weCurrent: ""            // project.json of the Wallpaper Engine wallpaper on screen
    function weRefresh() {
        if (!weStatusProc.running) weStatusProc.running = true;
        if (!weListProc.running) weListProc.running = true;
    }
    Process {
        id: weStatusProc
        command: ["macshell-helper", "wallpaper", "engine", "status"]
        stdout: StdioCollector { onStreamFinished: root.weInstalled = text.indexOf("installed") === 0 }
    }
    Process {
        id: weListProc
        command: ["macshell-helper", "wallpaper", "engine", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], lines = text.split("\\n");
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].replace(/\\r$/, "");
                    if (l.indexOf("W:") !== 0) continue;
                    var f = l.substring(2).split("\\t");
                    if (f.length >= 5) out.push({ id: f[0], title: f[1], type: f[2], preview: f[3], file: f[4] });
                }
                root.weItems = out;
            }
        }
    }
    // a local path (C:\\... on Windows, /home/... on Linux) as a file:// URL for Image
    function weUrl(p) { return p ? "file:///" + p.split(String.fromCharCode(92)).join("/").replace(/^\\/+/, "") : ""; }
    function weApply(w) {
        root.weCurrent = w.file;
        if (w.preview !== "") {                                              // the glass refracts its preview
            root.wallpaperPath = w.preview;
            try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = w.preview; } catch (e) {}
        }
        Quickshell.execDetached(["macshell-helper", "wallpaper", "engine", "apply", w.file]);
    }
    function wpApply(path) {
        if (root.weCurrent !== "") {                                         // a normal wallpaper replaces Wallpaper Engine's
            root.weCurrent = "";
            Quickshell.execDetached(["macshell-helper", "wallpaper", "engine", "stop"]);
        }
        var pair = wpPairOf(path);'''),

        # ── branding ──
        ('''source: root.darkMode ? Qt.resolvedUrl("apple-logo-white.svg") : Qt.resolvedUrl("apple-logo-black.svg")''',
         '''source: root.darkMode ? Qt.resolvedUrl("ff-logo-white.svg") : Qt.resolvedUrl("ff-logo-black.svg")'''),
        ('''    readonly property string logoPath: decodeURIComponent(String(Qt.resolvedUrl("assets/macshell-logo.png")).replace(/^file:\\/\\//, ""))''',
         '''    readonly property string logoPath: decodeURIComponent(String(Qt.resolvedUrl("assets/freeform-logo.png")).replace(/^file:\\/\\//, ""))'''),
        ('''            m.push(mi("About This Linux", "", function () {''',
         '''            m.push(mi("About This PC", "", function () {'''),
    ],
    "MacDock.qml": [
        ('''                            source: Qt.resolvedUrl(pal.dark ? "apple-logo-white.svg" : "apple-logo-black.svg")''',
         '''                            source: Qt.resolvedUrl(pal.dark ? "ff-logo-white.svg" : "ff-logo-black.svg")'''),
        ('''    readonly property string logoPath: decodeURIComponent(String(Qt.resolvedUrl("assets/macshell-logo.png")).replace(/^file:\\/\\//, ""))''',
         '''    readonly property string logoPath: decodeURIComponent(String(Qt.resolvedUrl("assets/freeform-logo.png")).replace(/^file:\\/\\//, ""))'''),

        # ── theme presets ──
        ('''    function setLook(k, v) { root[k] = v; if (bar) bar[k] = v; }''',
         '''    function setLook(k, v) { root[k] = v; if (bar) bar[k] = v; }
    // FreeForm theme presets: MacShell's look + Windows apps + Spotify (compat/helper/theme.py has the colours)
    property string themePreset: "default"
    readonly property var themePresets: builtinThemes.concat(hub && hub.themeStudio ? hub.themeStudio.themes : [])
    readonly property var builtinThemes: [
        { id: "black", name: "Black", mode: "dark", accent: "#D1D1D6", glass: 0.75, bg: "#000000", fg: "#FFFFFF", card: "#1A1A1A" },
        { id: "white", name: "White", mode: "light", accent: "#636366", glass: 0.7, bg: "#FFFFFF", fg: "#000000", card: "#E5E5EA" },
        { id: "graphite", name: "Graphite", mode: "dark", accent: "#8E8E93", glass: 0.55, bg: "#2C2C2E", fg: "#F2F2F7", card: "#48484A" },
        { id: "default", name: "Default", mode: "dark", accent: "#0A84FF", glass: 0.42, bg: "#1E1E1E", fg: "#F5F5F7", card: "#2A2A2C" }
    ]
    function applyThemePreset(id) {
        var t = null;
        for (var i = 0; i < themePresets.length; i++) if (themePresets[i].id === id) t = themePresets[i];
        if (!t) return;
        themePreset = id;
        setAppearance(t.mode);
        setLook("accent", t.accent);
        setLook("glassOpacity", t.glass);
        if (t.custom) Quickshell.execDetached(["macshell-helper", "theme", "apply-custom", JSON.stringify(t)]);
        else Quickshell.execDetached(["macshell-helper", "theme", "apply", id]);
    }'''),
        ('''            id: paneAppearance
            Column {
                spacing: 10
''',
         '''            id: paneAppearance
            Column {
                spacing: 10

                // FreeForm theme presets
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Theme")
                        subtitle: I18n.tr("One click for the whole desktop: the menu bar, Dock, apps, Windows apps and Spotify (with Spicetify).")
                        Row {
                            spacing: 12
                            Repeater {
                                model: root.themePresets
                                delegate: Column {
                                    id: tp
                                    required property var modelData
                                    spacing: 4
                                    Rectangle {
                                        width: 64; height: 42; radius: 8
                                        color: tp.modelData.bg
                                        border.width: root.themePreset === tp.modelData.id ? 2.5 : 1
                                        border.color: root.themePreset === tp.modelData.id ? pal.accent : pal.cardBorder
                                        Rectangle { x: 6; y: 6; width: parent.width - 12; height: 6; radius: 3; color: tp.modelData.card }
                                        Rectangle { x: 6; y: 16; width: 30; height: 4; radius: 2; color: tp.modelData.fg; opacity: 0.8 }
                                        Rectangle { x: 6; y: 24; width: 22; height: 4; radius: 2; color: tp.modelData.fg; opacity: 0.45 }
                                        Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6; width: 12; height: 12; radius: 6; color: tp.modelData.accent }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            // right-click a custom theme to edit it in Theme Studio
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton && tp.modelData.custom && root.hub && root.hub.themeStudio)
                                                    root.hub.themeStudio.open(root.hub.themeStudio.themes.indexOf(tp.modelData));
                                                else root.applyThemePreset(tp.modelData.id);
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: I18n.tr(tp.modelData.name)
                                        color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                                    }
                                }
                            }
                            Column {                           // make your own (Theme Studio)
                                spacing: 4
                                Rectangle {
                                    width: 64; height: 42; radius: 8
                                    color: "transparent"; border.width: 1; border.color: pal.cardBorder
                                    Text { anchors.centerIn: parent; text: "+"; color: pal.text2; font.pixelSize: 22 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.hub && root.hub.themeStudio) root.hub.themeStudio.open() }
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.tr("Custom\u2026"); color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11 }
                            }
                        }
                    }
                }
'''),
        # ── Settings > Wallpaper: Wallpaper Engine section ──
        ('''                Item {
                    width: parent.width; height: 30
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpapers"); topPadding: 0 }''',
         '''                // ── Wallpaper Engine (FreeForm) ──
                Item {
                    width: parent.width; height: 30
                    Component.onCompleted: if (root.bar) root.bar.weRefresh()
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpaper Engine"); topPadding: 0 }
                    SButton {
                        t: pal
                        visible: root.bar && root.bar.weItems.length > 0
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Workshop")
                        onClicked: Qt.openUrlExternally("steam://url/SteamWorkshopPage/431960")
                    }
                }
                SCard {
                    t: pal
                    visible: !(root.bar && root.bar.weItems.length > 0)
                    SRow {
                        t: pal
                        title: root.bar && root.bar.weInstalled ? I18n.tr("No Wallpaper Engine wallpapers yet") : I18n.tr("Wallpaper Engine")
                        subtitle: root.bar && root.bar.weInstalled ? I18n.tr("Subscribe to wallpapers in the Steam Workshop and they show up here.")
                                                                   : I18n.tr("Animated and interactive wallpapers from the Steam Workshop. A paid app on Steam.")
                        SButton {
                            t: pal
                            text: root.bar && root.bar.weInstalled ? I18n.tr("Open Workshop") : I18n.tr("View on Steam")
                            onClicked: Qt.openUrlExternally(root.bar && root.bar.weInstalled ? "steam://url/SteamWorkshopPage/431960" : "steam://store/431960")
                        }
                    }
                }
                GridView {
                    id: weGrid
                    visible: root.bar && root.bar.weItems.length > 0
                    width: parent.width
                    cellWidth: Math.floor((width - 20) / (width > 1100 ? 4 : 3))
                    cellHeight: Math.round(cellWidth * 0.5625) + 32
                    height: visible ? Math.min(contentHeight, cellHeight * 2) : 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.bar ? root.bar.weItems : []
                    delegate: Item {
                        id: we
                        required property var modelData
                        width: weGrid.cellWidth; height: weGrid.cellHeight
                        readonly property bool cur: root.bar && root.bar.weCurrent === modelData.file
                        readonly property bool gif: /\\.gif$/i.test(modelData.preview)
                        Item {
                            id: weBox
                            x: 5; y: 5
                            width: parent.width - 10; height: parent.height - 32
                            scale: weMa.pressed ? 0.98 : 1
                            Item {
                                id: weMask
                                anchors.fill: parent; visible: false
                                layer.enabled: true; layer.smooth: true
                                Rectangle { anchors.fill: parent; radius: 9; color: "black" }
                            }
                            Item {
                                anchors.fill: parent
                                layer.enabled: true; layer.smooth: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: weMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                Rectangle { anchors.fill: parent; color: pal.ctrl }
                                Image {
                                    anchors.fill: parent
                                    visible: we.modelData.preview !== ""
                                    source: root.bar ? root.bar.weUrl(we.modelData.preview) : ""
                                    sourceSize.width: 260
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; smooth: true
                                }
                                Loader {                                      // previews move while the pointer is on them
                                    anchors.fill: parent
                                    active: we.gif && weMa.containsMouse && prefsWindow.visible
                                    sourceComponent: AnimatedImage {
                                        source: root.bar ? root.bar.weUrl(we.modelData.preview) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: false; playing: true
                                    }
                                }
                                Rectangle {
                                    x: 6; y: 6
                                    width: weBadge.implicitWidth + 12; height: 18; radius: 9
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                    Text {
                                        id: weBadge
                                        anchors.centerIn: parent
                                        text: we.modelData.type === "video" ? I18n.tr("\\u25B6  Video") : we.modelData.type === "web" ? I18n.tr("Web") : I18n.tr("Scene")
                                        color: "white"; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 9; font.weight: Font.DemiBold
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: we.cur ? -3 : 0
                                radius: we.cur ? 12 : 9
                                color: "transparent"
                                border.width: we.cur ? 2.5 : 1
                                border.color: we.cur ? pal.accent : pal.cardBorder
                            }
                            MouseArea {
                                id: weMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.bar) root.bar.weApply(we.modelData)
                            }
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            x: 5; width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: we.modelData.title
                            color: we.cur ? pal.text : pal.text2
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                        }
                    }
                }

                Item {
                    width: parent.width; height: 30
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpapers"); topPadding: 0 }'''),
    ],

    "AboutApp.qml": [
        ('''        command: ["sh", root.scriptPath]''',
         '''        command: Qt.platform.os === "windows" ? ["macshell-helper", "about"] : ["sh", root.scriptPath]'''),
        ('''        title: "About This Linux"''', '''        title: "About This PC"'''),
        ('''                    text: "MacShell"
''', '''                    text: "FreeForm"
'''),
        ('''                        source: userLogo.visible ? "" : root.distroLogo''',
         '''                        source: userLogo.visible ? "" : Qt.resolvedUrl("assets/freeform-logo.png")'''),
        ('''                    text: "Linux® is a registered trademark of Linus Torvalds.\\nMacShell 0.2.9"''',
         '''                    text: "FreeForm, built on MacShell 0.2.9 (MIT) and Quickshell (LGPL).\\n" + (root.info.osname || "")'''),
    ],
}

if __name__ == "__main__":
    sys.exit(0 if apply(check="--check" in sys.argv, edits_by_file=EDITS) else 1)
