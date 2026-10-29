// Theme Studio — make your own FreeForm theme, previewed on the FreeForm desktop or a Spotify-style window.
//
//   qs -c MacShell ipc call themestudio open        (also: Settings > Appearance > Theme > Custom…)
//
// Start from a preset (or "Surprise me"), pick the background, sidebar, cards, text, secondary text
// and accent colours, Light/Dark, how glassy panels are, and a wallpaper that comes with the theme.
// A readability check warns when text and background are too close.
// The preview is a plain drawing of a music app: album covers and song names are grey blocks,
// so no real music or artwork is shown. Saved themes appear next to Black / White / Graphite and
// apply the same way (MacShell, Windows apps, and Spotify through Spicetify when installed).
// Saved to ~/.config/macshell/themes.json. Share one with Export (a .fftheme file in
// Documents/FreeForm Themes); themes put in that folder show up under Import.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string home: Quickshell.env("HOME") || Quickshell.env("USERPROFILE")

    property var themes: []                       // { id, name, mode, accent, glass, bg, fg, card, side, sub, custom: true }
    property var draft: newDraft()
    property int editing: -1                      // index in themes, -1 = a new one

    function newDraft() {
        return { id: "", name: "My Theme", mode: "dark", accent: "#1DB954", glass: 0.6,
                 bg: "#121212", side: "#000000", card: "#1F1F1F", fg: "#FFFFFF", sub: "#A7A7A7", custom: true };
    }
    function open(index) {
        editing = index === undefined ? -1 : index;
        draft = editing >= 0 ? JSON.parse(JSON.stringify(themes[editing])) : newDraft();
        if (!win.visible) placeWindow();
        win.visible = true; win.raise(); win.requestActivate();
        listShared();
    }
    // open fully on screen, below the menu bar and above the Dock (smaller screens get a smaller window)
    function placeWindow() {
        var s = Quickshell.screens.length ? Quickshell.screens[0] : null; if (!s) return;
        var top = 34, bottom = 90;
        win.width = Math.min(win.width, s.width - 40);
        win.height = Math.min(win.height, s.height - top - bottom);
        win.x = Math.round((s.width - win.width) / 2);
        win.y = Math.round(top + (s.height - top - bottom - win.height) / 2);
    }
    function close() { win.visible = false; }
    property string previewTab: "desktop"         // desktop | spotify

    // ready-made starting points (all editable)
    readonly property var starters: [
        { name: "Midnight", mode: "dark", bg: "#0B0D12", side: "#05060A", card: "#171A22", fg: "#F5F7FA", sub: "#8A93A6", accent: "#0A84FF", glass: 0.6, wallpaper: "FreeForm Sierra.jpg" },
        { name: "Snow", mode: "light", bg: "#FFFFFF", side: "#F2F2F7", card: "#E9E9EE", fg: "#1D1D1F", sub: "#6E6E73", accent: "#0A84FF", glass: 0.5, wallpaper: "FreeForm Sierra.jpg" },
        { name: "Graphite", mode: "dark", bg: "#1C1C1E", side: "#141414", card: "#2C2C2E", fg: "#F2F2F2", sub: "#9A9A9F", accent: "#8E8E93", glass: 0.55, wallpaper: "FreeForm Yosemite.jpg" },
        { name: "Ocean", mode: "dark", bg: "#071A24", side: "#04121A", card: "#0E2A38", fg: "#E8F6FB", sub: "#7FA9B8", accent: "#2EC5E6", glass: 0.6, wallpaper: "FreeForm Big Sur.jpg" },
        { name: "Sunset", mode: "dark", bg: "#1A0F14", side: "#12080C", card: "#2A1820", fg: "#FFF1EC", sub: "#C29A92", accent: "#FF7A45", glass: 0.55, wallpaper: "FreeForm Big Sur.jpg" },
        { name: "Forest", mode: "dark", bg: "#0E1712", side: "#08100B", card: "#18261D", fg: "#EEF6EF", sub: "#8FA897", accent: "#30D158", glass: 0.55, wallpaper: "FreeForm Yosemite.jpg" },
        { name: "Paper", mode: "light", bg: "#FBF8F2", side: "#F1ECE2", card: "#E8E1D3", fg: "#2B2620", sub: "#7C7366", accent: "#C8641E", glass: 0.4, wallpaper: "FreeForm Yosemite.jpg" }
    ]
    function useStarter(st) {
        var d = JSON.parse(JSON.stringify(st)); d.id = draft.id; d.custom = true;
        d.name = editing >= 0 ? draft.name : st.name; draft = d;
    }
    // a random but harmonious palette: one hue for the accent, a tinted near-black or near-white base
    function surprise() {
        var h = Math.random(), dark = Math.random() < 0.7;
        var c = function (hh, ss, ll) { return String(Qt.hsla(hh % 1, ss, ll, 1)).toUpperCase().slice(0, 7); };
        var d = JSON.parse(JSON.stringify(draft));
        d.mode = dark ? "dark" : "light";
        d.bg = dark ? c(h, 0.25, 0.07) : c(h, 0.2, 0.97);
        d.side = dark ? c(h, 0.25, 0.04) : c(h, 0.18, 0.93);
        d.card = dark ? c(h, 0.22, 0.13) : c(h, 0.16, 0.89);
        d.fg = dark ? c(h, 0.15, 0.95) : c(h, 0.2, 0.12);
        d.sub = dark ? c(h, 0.12, 0.62) : c(h, 0.1, 0.42);
        d.accent = c(h + 0.5 + (Math.random() - 0.5) * 0.2, 0.75, dark ? 0.6 : 0.48);
        draft = d;
    }
    // WCAG contrast ratio between two colours (4.5+ reads comfortably)
    function lum(col) {
        var q = Qt.color(col), f = function (v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        return 0.2126 * f(q.r) + 0.7152 * f(q.g) + 0.0722 * f(q.b);
    }
    function contrast(a, b) { var x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
    readonly property real readability: contrast(draft.fg || "#FFFFFF", draft.bg || "#000000")
    readonly property var wallpapers: ["FreeForm Yosemite.jpg", "FreeForm Big Sur.jpg", "FreeForm Sierra.jpg"]
    function wallpaperFile(name) {
        return decodeURIComponent(String(Qt.resolvedUrl("assets/wallpapers/" + name))).replace(/^file:(\/\/)?/, "").replace(/^\/([A-Za-z]:)/, "$1");
    }
    function set(k, v) { var d = JSON.parse(JSON.stringify(draft)); d[k] = v; draft = d; }
    function save(apply) {
        var d = JSON.parse(JSON.stringify(draft));
        if (!d.id) d.id = "custom-" + Date.now().toString(36);
        var l = themes.slice();
        if (editing >= 0) l[editing] = d; else { l.push(d); editing = l.length - 1; }
        themes = l; draft = d;
        store.setText(JSON.stringify({ themes: l }, null, 1));
        if (apply && dock) dock.applyThemePreset(d.id);
        if (apply && d.wallpaper && hub && hub.bar) {                   // the theme's wallpaper comes along
            var wp = wallpaperFile(d.wallpaper);
            hub.bar.wallpaperPath = wp; if (dock) dock.wallpaperPath = wp;
        }
    }
    function remove() {
        if (editing < 0) return;
        var l = themes.slice(); l.splice(editing, 1); themes = l;
        store.setText(JSON.stringify({ themes: l }, null, 1));
        close();
    }

    // ── sharing: Documents/FreeForm Themes/*.fftheme ──
    readonly property string shareDir: home + "/Documents/FreeForm Themes"
    property var shared: []
    property string pendingText: ""
    property string pendingName: ""
    function winPath(p) { return String(p).split("/").join(String.fromCharCode(92)); }
    function exportTheme() {
        var d = JSON.parse(JSON.stringify(draft)); delete d.id;
        pendingName = String(d.name || "Theme").replace(/[^A-Za-z0-9 _-]/g, "").trim() || "Theme";
        pendingText = JSON.stringify(d, null, 1);
        mkdirProc.command = Qt.platform.os === "windows" ? ["cmd.exe", "/c", "if not exist \"" + winPath(shareDir) + "\" mkdir \"" + winPath(shareDir) + "\""]
                                                         : ["mkdir", "-p", shareDir];
        mkdirProc.running = true;
    }
    property Process mkdirProc: Process {
        onExited: {
            exportFile.path = root.shareDir + "/" + root.pendingName + ".fftheme";
            exportFile.setText(root.pendingText);
            Qt.openUrlExternally("file:///" + root.shareDir.replace(/^\/+/, ""));
            root.listShared();
        }
    }
    property FileView exportFile: FileView { printErrors: false }
    function listShared() { listProc.running = false; listProc.running = true; }
    property Process listProc: Process {
        command: Qt.platform.os === "windows"
            ? ["cmd.exe", "/c", "dir", "/b", root.winPath(root.shareDir) + String.fromCharCode(92) + "*.fftheme"]
            : ["sh", "-c", 'cd "$1" 2>/dev/null && ls -1 *.fftheme 2>/dev/null', "sh", root.shareDir]
        stdout: StdioCollector {
            onStreamFinished: root.shared = text.split(/\r?\n/).filter(function (l) { return /\.fftheme$/i.test(l); }).map(function (f) {
                return { path: root.shareDir + "/" + f, name: f.replace(/\.fftheme$/i, "") };
            })
        }
    }
    property FileView importFile: FileView { printErrors: false; blockLoading: true }
    function importTheme(path) {
        importFile.path = path;
        var d = null;
        try { d = JSON.parse(importFile.text()); } catch (e) { return; }
        if (!d || !d.bg || !d.fg) return;
        d.custom = true; d.id = ""; editing = -1; draft = d;           // opens in the editor: Save keeps it
    }

    FileView {
        id: store
        path: root.home + "/.config/macshell/themes.json"
        printErrors: false
        onLoaded: { try { root.themes = JSON.parse(text()).themes || []; } catch (e) {} }
    }

    Window {
        id: win
        title: "Theme Studio"
        width: 1120; height: 720
        minimumWidth: 900; minimumHeight: 560
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        // Windows 11's acrylic blur behind the window (see quickshell/src/windows/init.cpp): the glass look
        property int ffBackdrop: 3
        property bool ffDarkGlass: dark

        readonly property bool dark: root.dock ? root.dock.darkMode : true
        // glass while it's a window; solid when maximized or fullscreen, so the desktop doesn't show through
        readonly property bool solid: visibility === Window.Maximized || visibility === Window.FullScreen
        readonly property color ui: dark ? Qt.rgba(0.12, 0.12, 0.13, solid ? 1 : 0.55) : Qt.rgba(1, 1, 1, solid ? 1 : 0.6)
        readonly property color uiSide: dark ? Qt.rgba(0.17, 0.17, 0.18, solid ? 1 : 0.45) : Qt.rgba(0.95, 0.95, 0.96, solid ? 1 : 0.5)
        readonly property color uiText: dark ? "#F5F5F7" : "#1D1D1F"
        readonly property color uiText2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
        readonly property color uiField: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
        readonly property color uiSep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
        readonly property color accent: root.dock ? root.dock.accent : "#0A84FF"

        // one colour setting: name, swatches and a hex field
        component ColorRow: Column {
            id: cr
            property string label: ""
            property string key: ""
            readonly property string value: root.draft[key] || "#000000"
            width: parent ? parent.width : 300
            spacing: 6
            Row {
                spacing: 8
                Rectangle { width: 18; height: 18; radius: 9; color: cr.value; border.width: 1; border.color: win.uiSep; anchors.verticalCenter: parent.verticalCenter }
                Text { text: I18n.tr(cr.label); color: win.uiText; font.family: root.fam; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            }
            Flow {
                width: parent.width; spacing: 5
                Repeater {
                    model: ["#000000", "#121212", "#1C1C1E", "#2C2C2E", "#48484A", "#8E8E93", "#C7C7CC", "#E5E5EA", "#F5F5F7", "#FFFFFF",
                            "#1DB954", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F", "#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#64D2FF"]
                    delegate: Rectangle {
                        required property string modelData
                        width: 20; height: 20; radius: 5; color: modelData
                        border.width: cr.value.toUpperCase() === modelData ? 2.5 : 1
                        border.color: cr.value.toUpperCase() === modelData ? win.accent : win.uiSep
                        MouseArea { anchors.fill: parent; onClicked: root.set(cr.key, parent.modelData) }
                    }
                }
                Rectangle {
                    width: 82; height: 20; radius: 5; color: win.uiField
                    TextInput {
                        anchors.fill: parent; anchors.leftMargin: 6
                        verticalAlignment: TextInput.AlignVCenter
                        text: cr.value; color: win.uiText; font.family: root.fam; font.pixelSize: 11; selectByMouse: true
                        onEditingFinished: if (/^#[0-9a-fA-F]{6}$/.test(text)) root.set(cr.key, text.toUpperCase())
                    }
                }
            }
        }
        component Btn: Rectangle {
            id: b
            property string label: ""
            property bool primary: false
            signal clicked()
            width: bt.implicitWidth + 28; height: 30; radius: 15
            color: primary ? win.accent : win.uiField
            Text { id: bt; anchors.centerIn: parent; text: b.label; color: b.primary ? "white" : win.uiText; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
        }

        Rectangle {
            anchors.fill: parent; radius: 12; color: win.ui
            border.width: 1; border.color: win.uiSep
            clip: true
            // Windows caption buttons, top right
            WinCaption { z: 10; window: win; dark: win.dark; anchors.top: parent.top; anchors.right: parent.right; anchors.rightMargin: 1 }

            // ── left: the controls ──
            Rectangle {
                id: panel
                width: 360; height: parent.height; color: win.uiSide
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.uiSep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Flickable {
                    x: 20; y: 50; width: parent.width - 40; height: parent.height - 50 - 64 - exportFlow.height - 12
                    contentHeight: ctl.height; clip: true
                    Column {
                        id: ctl
                        width: parent.width; spacing: 14
                        Text { text: I18n.tr("Theme Studio"); color: win.uiText; font.family: root.fam; font.pixelSize: 22; font.weight: Font.Bold }
                        // your saved themes: click one to edit it
                        Flow {
                            visible: root.themes.length > 0
                            width: parent.width; spacing: 6
                            Text { text: I18n.tr("Yours:"); color: win.uiText2; font.family: root.fam; font.pixelSize: 12; height: 26; verticalAlignment: Text.AlignVCenter }
                            Repeater {
                                model: root.themes
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: yt.implicitWidth + 30; height: 26; radius: 13
                                    color: root.editing === index ? win.accent : win.uiField
                                    Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: parent.modelData.accent }
                                    Text { id: yt; x: 22; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; color: root.editing === parent.index ? "white" : win.uiText; font.family: root.fam; font.pixelSize: 12 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.open(parent.index) }
                                }
                            }
                            Rectangle {
                                width: 26; height: 26; radius: 13; color: win.uiField
                                Text { anchors.centerIn: parent; text: "+"; color: win.uiText; font.pixelSize: 15 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.open() }
                            }
                        }
                        Text { text: I18n.tr("START FROM"); color: win.uiText2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Flow {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: root.starters
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 64; height: 50; radius: 9; color: modelData.bg
                                    border.width: 1; border.color: win.uiSep
                                    Rectangle { x: 6; y: 6; width: 18; height: 18; radius: 9; color: parent.modelData.accent }
                                    Rectangle { x: 28; y: 9; width: 28; height: 5; radius: 2.5; color: parent.modelData.fg }
                                    Rectangle { x: 28; y: 17; width: 18; height: 4; radius: 2; color: parent.modelData.sub }
                                    Text { x: 6; y: 30; text: parent.modelData.name; color: parent.modelData.fg; font.family: root.fam; font.pixelSize: 11 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.useStarter(parent.modelData) }
                                }
                            }
                            Rectangle {
                                width: 64; height: 50; radius: 9; color: win.uiField
                                Text { anchors.centerIn: parent; horizontalAlignment: Text.AlignHCenter; text: "\u2728\n" + I18n.tr("Surprise"); color: win.uiText; font.family: root.fam; font.pixelSize: 11 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.surprise() }
                            }
                        }
                        Rectangle {
                            width: parent.width; height: 30; radius: 7; color: win.uiField
                            TextInput {
                                anchors.fill: parent; anchors.leftMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.draft.name; color: win.uiText; font.family: root.fam; font.pixelSize: 14; selectByMouse: true
                                onTextEdited: root.set("name", text)
                            }
                        }
                        Row {
                            spacing: 6
                            Repeater {
                                model: [{ v: "dark", l: "Dark" }, { v: "light", l: "Light" }]
                                delegate: Btn { required property var modelData; label: I18n.tr(modelData.l); primary: root.draft.mode === modelData.v; onClicked: root.set("mode", modelData.v) }
                            }
                        }
                        ColorRow { label: "Background"; key: "bg" }
                        ColorRow { label: "Sidebar"; key: "side" }
                        ColorRow { label: "Cards & bars"; key: "card" }
                        ColorRow { label: "Text"; key: "fg" }
                        ColorRow { label: "Secondary text"; key: "sub" }
                        ColorRow { label: "Accent"; key: "accent" }
                        // readability: text against the background
                        Row {
                            spacing: 8
                            Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter
                                        color: root.readability >= 7 ? "#30D158" : root.readability >= 4.5 ? "#FFD60A" : "#FF453A" }
                            Text {
                                color: win.uiText2; font.family: root.fam; font.pixelSize: 12
                                text: (root.readability >= 7 ? I18n.tr("Text is easy to read") : root.readability >= 4.5 ? I18n.tr("Text reads OK")
                                       : I18n.tr("Text is hard to read: make Text and Background more different")) + "  (" + root.readability.toFixed(1) + ":1)"
                            }
                        }
                        // how see-through menus, the Dock and panels are
                        Column {
                            width: parent.width; spacing: 6
                            Text { text: I18n.tr("Glass") + "  " + Math.round((root.draft.glass !== undefined ? root.draft.glass : 0.6) * 100) + "%"; color: win.uiText; font.family: root.fam; font.pixelSize: 13 }
                            Rectangle {
                                id: glassTrack
                                width: parent.width; height: 6; radius: 3; color: win.uiField
                                readonly property real v: root.draft.glass !== undefined ? root.draft.glass : 0.6
                                Rectangle { width: parent.width * glassTrack.v; height: 6; radius: 3; color: win.accent }
                                Rectangle { x: parent.width * glassTrack.v - 8; y: -5; width: 16; height: 16; radius: 8; color: "white"; border.width: 1; border.color: win.uiSep }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    function pick(mx) { root.set("glass", Math.round(Math.max(0, Math.min(1, (mx - 8) / glassTrack.width)) * 100) / 100); }
                                    onPressed: mouse => pick(mouse.x); onPositionChanged: mouse => pick(mouse.x)
                                }
                            }
                        }
                        // the wallpaper that comes with the theme
                        Text { text: I18n.tr("WALLPAPER"); color: win.uiText2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Flow {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: root.wallpapers
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 88; height: 56; radius: 8; clip: true; color: win.uiField
                                    border.width: root.draft.wallpaper === modelData ? 2.5 : 0; border.color: win.accent
                                    Image { anchors.fill: parent; anchors.margins: parent.border.width; source: Qt.resolvedUrl("assets/wallpapers/" + parent.modelData); fillMode: Image.PreserveAspectCrop; sourceSize.width: 200; asynchronous: true }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.set("wallpaper", parent.modelData) }
                                }
                            }
                            Rectangle {
                                width: 88; height: 56; radius: 8; color: win.uiField
                                border.width: !root.draft.wallpaper ? 2.5 : 0; border.color: win.accent
                                Text { anchors.centerIn: parent; text: I18n.tr("Keep mine"); color: win.uiText; font.family: root.fam; font.pixelSize: 11 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.set("wallpaper", "") }
                            }
                        }
                    }
                }
                // share: export this theme, import ones from Documents/FreeForm Themes
                Flow {
                    id: exportFlow
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 62; x: 20; width: parent.width - 40
                    spacing: 6
                    Btn { label: I18n.tr("Export\u2026"); onClicked: root.exportTheme() }
                    Repeater {
                        model: root.shared
                        delegate: Btn { required property var modelData; label: "+ " + modelData.name; onClicked: root.importTheme(modelData.path) }
                    }
                }
                Row {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 18; x: 20
                    spacing: 8
                    Btn { label: I18n.tr("Save"); onClicked: root.save(false) }
                    Btn { label: I18n.tr("Save & Apply"); primary: true; onClicked: root.save(true) }
                    Btn { visible: root.editing >= 0; label: I18n.tr("Delete"); onClicked: root.remove() }
                }
            }

            // ── right: the preview, a music app drawn with placeholders ──
            Item {
                id: stageArea
                x: panel.width; width: parent.width - panel.width; height: parent.height
                Text { x: 28; y: 22; text: I18n.tr("Preview"); color: win.uiText2; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 168; y: 12; spacing: 6
                    Btn { label: I18n.tr("Desktop"); primary: root.previewTab === "desktop"; onClicked: root.previewTab = "desktop" }
                    Btn { label: I18n.tr("Spotify"); primary: root.previewTab === "spotify"; onClicked: root.previewTab = "spotify" }
                }
                // the FreeForm desktop in this theme: wallpaper, menu bar, a window, a menu and the Dock
                Rectangle {
                    id: deskPrev
                    visible: root.previewTab === "desktop"
                    readonly property var t: root.draft
                    readonly property real g: t.glass !== undefined ? t.glass : 0.6
                    function glassy(c, k) { var q = Qt.color(c); return Qt.rgba(q.r, q.g, q.b, 1 - deskPrev.g * k); }
                    x: 28; y: 54; width: parent.width - 56; height: parent.height - 82
                    radius: 12; clip: true; color: "#222"
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.35; shadowVerticalOffset: 8 }
                    Image {
                        id: dpWall
                        anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 1200
                        source: Qt.resolvedUrl("assets/wallpapers/" + (deskPrev.t.wallpaper || "FreeForm Yosemite.jpg"))
                    }
                    // menu bar
                    Rectangle {
                        width: parent.width; height: 26; color: deskPrev.glassy(deskPrev.t.side, 0.55)
                        Row {
                            x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                            Text { text: "FF"; color: deskPrev.t.fg; font.family: root.fam; font.pixelSize: 12; font.weight: Font.Black }
                            Text { text: "Finder"; color: deskPrev.t.fg; font.family: root.fam; font.pixelSize: 12; font.weight: Font.Bold }
                            Repeater { model: ["File", "Edit", "View", "Window"]; Text { required property string modelData; text: modelData; color: deskPrev.t.fg; font.family: root.fam; font.pixelSize: 12 } }
                        }
                        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "Thu 9:41"; color: deskPrev.t.fg; font.family: root.fam; font.pixelSize: 12 }
                    }
                    // an open menu
                    Rectangle {
                        x: 92; y: 30; width: 170; height: 118; radius: 9; color: deskPrev.glassy(deskPrev.t.card, 0.45)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                        Column {
                            x: 6; y: 6; width: parent.width - 12
                            Repeater {
                                model: ["New Window", "Open\u2026", "Save", "Close"]
                                delegate: Rectangle {
                                    required property string modelData; required property int index
                                    width: parent.width; height: 26; radius: 5; color: index === 1 ? deskPrev.t.accent : "transparent"
                                    Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData; color: parent.index === 1 ? "white" : deskPrev.t.fg; font.family: root.fam; font.pixelSize: 12 }
                                }
                            }
                        }
                    }
                    // a window
                    Rectangle {
                        x: parent.width * 0.3; y: parent.height * 0.2; width: parent.width * 0.6; height: parent.height * 0.55
                        radius: 12; color: deskPrev.t.bg; clip: true; border.width: 1; border.color: Qt.rgba(0.5, 0.5, 0.5, 0.3)
                        Rectangle {
                            width: parent.width * 0.3; height: parent.height; color: deskPrev.glassy(deskPrev.t.side, 0.35)
                            Row { x: 12; y: 12; spacing: 6; Repeater { model: ["#FF5F57", "#FEBC2E", "#28C840"]; Rectangle { required property string modelData; width: 10; height: 10; radius: 5; color: modelData } } }
                            Column {
                                x: 10; y: 38; width: parent.width - 20; spacing: 4
                                Repeater {
                                    model: ["Desktop", "Documents", "Downloads", "Pictures"]
                                    delegate: Rectangle {
                                        required property string modelData; required property int index
                                        width: parent.width; height: 24; radius: 6; color: index === 0 ? deskPrev.t.card : "transparent"
                                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData; color: deskPrev.t.fg; font.family: root.fam; font.pixelSize: 12 }
                                    }
                                }
                            }
                        }
                        Column {
                            x: parent.width * 0.3 + 18; y: 16; spacing: 8; width: parent.width * 0.7 - 36
                            Text { text: "Desktop"; color: deskPrev.t.fg; font.family: root.fam; font.pixelSize: 17; font.weight: Font.Bold }
                            Text { text: "4 items, 120 GB available"; color: deskPrev.t.sub; font.family: root.fam; font.pixelSize: 12 }
                            Grid {
                                columns: 3; spacing: 10
                                Repeater { model: 6; Rectangle { width: 54; height: 44; radius: 8; color: deskPrev.t.card } }
                            }
                            Rectangle {
                                width: 110; height: 28; radius: 14; color: deskPrev.t.accent
                                Text { anchors.centerIn: parent; text: "Open"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                            }
                        }
                    }
                    // the Dock
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        width: 290; height: 50; radius: 16; color: deskPrev.glassy(deskPrev.t.card, 0.6)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                        Row {
                            anchors.centerIn: parent; spacing: 8
                            Repeater { model: ["#1DB954", "#5865F2", "#4285F4", "#1B2838", "#8E8E93"]; Rectangle { required property string modelData; width: 36; height: 36; radius: 9; color: modelData } }
                        }
                    }
                }
                Rectangle {
                    id: app
                    visible: root.previewTab === "spotify"
                    readonly property var t: root.draft
                    x: 28; y: 54; width: parent.width - 56; height: parent.height - 82
                    radius: 12; color: t.bg; clip: true
                    border.width: 1; border.color: Qt.rgba(0.5, 0.5, 0.5, 0.25)
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.35; shadowVerticalOffset: 8 }
                    readonly property color ph: Qt.rgba(Qt.color(t.sub).r, Qt.color(t.sub).g, Qt.color(t.sub).b, 0.28)   // placeholder grey
                    readonly property color ph2: Qt.rgba(Qt.color(t.sub).r, Qt.color(t.sub).g, Qt.color(t.sub).b, 0.16)

                    // sidebar: library with grey covers
                    Rectangle {
                        id: pside
                        width: 200; height: parent.height - pbar.height; color: app.t.side
                        Column {
                            x: 14; y: 16; width: parent.width - 28; spacing: 10
                            Rectangle { width: 70; height: 10; radius: 5; color: app.t.fg }
                            Repeater {
                                model: 7
                                delegate: Row {
                                    required property int index
                                    spacing: 10
                                    Rectangle { width: 40; height: 40; radius: 6; color: app.ph }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                        Rectangle { width: 90 - (parent.parent.index % 3) * 14; height: 8; radius: 4; color: parent.parent.index === 1 ? app.t.accent : app.ph }
                                        Rectangle { width: 54; height: 6; radius: 3; color: app.ph2 }
                                    }
                                }
                            }
                        }
                    }
                    // main: header + track list
                    Item {
                        x: pside.width; width: parent.width - pside.width; height: parent.height - pbar.height
                        Rectangle {
                            width: parent.width; height: 170
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(Qt.color(app.t.accent).r, Qt.color(app.t.accent).g, Qt.color(app.t.accent).b, 0.35) }
                                GradientStop { position: 1; color: app.t.bg }
                            }
                            Rectangle { x: 22; y: 26; width: 120; height: 120; radius: 8; color: app.ph }
                            Column {
                                x: 162; y: 60; spacing: 10
                                Rectangle { width: 60; height: 7; radius: 3; color: app.ph }
                                Rectangle { width: 220; height: 22; radius: 6; color: app.t.fg }
                                Rectangle { width: 140; height: 8; radius: 4; color: app.ph }
                            }
                        }
                        Row {
                            x: 22; y: 182; spacing: 16
                            Rectangle { width: 46; height: 46; radius: 23; color: app.t.accent
                                Canvas { anchors.fill: parent; property color c: app.t.bg; onCChanged: requestPaint()
                                    onPaint: { var x = getContext("2d"); x.reset(); x.fillStyle = c; x.beginPath(); x.moveTo(18, 14); x.lineTo(32, 23); x.lineTo(18, 32); x.closePath(); x.fill(); } } }
                            Rectangle { width: 26; height: 26; radius: 13; anchors.verticalCenter: parent.verticalCenter; color: "transparent"; border.width: 2; border.color: app.t.sub }
                            Rectangle { width: 26; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: app.t.sub }
                        }
                        Column {
                            x: 22; y: 246; width: parent.width - 44; spacing: 4
                            Repeater {
                                model: 7
                                delegate: Rectangle {
                                    required property int index
                                    width: parent.width; height: 44; radius: 6
                                    color: index === 2 ? app.t.card : "transparent"
                                    Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 8; radius: 3; color: app.ph2 }
                                    Rectangle { x: 34; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4; color: app.ph }
                                    Column {
                                        x: 78; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                        Rectangle { width: 150 - (parent.parent.index % 4) * 18; height: 8; radius: 4; color: parent.parent.index === 2 ? app.t.accent : app.t.fg; opacity: parent.parent.index === 2 ? 1 : 0.85 }
                                        Rectangle { width: 90; height: 6; radius: 3; color: app.ph }
                                    }
                                    Rectangle { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 6; radius: 3; color: app.ph2 }
                                }
                            }
                        }
                    }
                    // now-playing bar
                    Rectangle {
                        id: pbar
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 74; color: app.t.side
                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.5, 0.5, 0.5, 0.2) }
                        Row {
                            x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                            Rectangle { width: 48; height: 48; radius: 5; color: app.ph }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                Rectangle { width: 110; height: 8; radius: 4; color: app.t.fg }
                                Rectangle { width: 70; height: 6; radius: 3; color: app.ph } }
                        }
                        Column {
                            anchors.centerIn: parent; spacing: 8
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter; spacing: 18
                                Rectangle { width: 14; height: 14; radius: 3; color: app.t.sub; anchors.verticalCenter: parent.verticalCenter }
                                Rectangle { width: 30; height: 30; radius: 15; color: app.t.fg }
                                Rectangle { width: 14; height: 14; radius: 3; color: app.t.sub; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Rectangle {
                                width: 280; height: 4; radius: 2; color: app.ph
                                Rectangle { width: parent.width * 0.38; height: 4; radius: 2; color: app.t.accent }
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
                            width: 90; height: 4; radius: 2; color: app.ph
                            Rectangle { width: parent.width * 0.7; height: 4; radius: 2; color: app.t.fg }
                        }
                    }
                }
            }
        }
    }
}
