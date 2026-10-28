// Theme Studio — make your own FreeForm theme, previewed on a Spotify-style window.
//
//   qs -c MacShell ipc call themestudio open        (also: Settings > Appearance > Theme > Custom…)
//
// Pick the background, sidebar, cards, text, secondary text and accent colours and Light/Dark.
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
        win.visible = true; win.raise(); win.requestActivate();
        listShared();
    }
    function close() { win.visible = false; }
    function set(k, v) { var d = JSON.parse(JSON.stringify(draft)); d[k] = v; draft = d; }
    function save(apply) {
        var d = JSON.parse(JSON.stringify(draft));
        if (!d.id) d.id = "custom-" + Date.now().toString(36);
        var l = themes.slice();
        if (editing >= 0) l[editing] = d; else { l.push(d); editing = l.length - 1; }
        themes = l; draft = d;
        store.setText(JSON.stringify({ themes: l }, null, 1));
        if (apply && dock) dock.applyThemePreset(d.id);
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
        width: 1040; height: 660
        minimumWidth: 900; minimumHeight: 560
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        readonly property bool dark: root.dock ? root.dock.darkMode : true
        readonly property color ui: dark ? "#1E1E1E" : "#FFFFFF"
        readonly property color uiSide: dark ? "#2A2A2C" : "#F0F0F2"
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

            // ── left: the controls ──
            Rectangle {
                id: panel
                width: 340; height: parent.height; color: win.uiSide
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.uiSep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Row {
                    x: 18; y: 18; spacing: 8
                    Repeater {
                        model: ["#FF5F57", "#FEBC2E", "#28C840"]
                        delegate: Rectangle { required property string modelData; required property int index; width: 14; height: 14; radius: 7; color: index !== 1 && win.active ? modelData : Qt.rgba(0.5, 0.5, 0.5, 0.35) }
                    }
                }
                MouseArea { x: 16; y: 16; width: 20; height: 18; onClicked: win.visible = false }
                Flickable {
                    x: 20; y: 50; width: parent.width - 40; height: parent.height - 50 - 64
                    contentHeight: ctl.height; clip: true
                    Column {
                        id: ctl
                        width: parent.width; spacing: 14
                        Text { text: I18n.tr("Theme Studio"); color: win.uiText; font.family: root.fam; font.pixelSize: 22; font.weight: Font.Bold }
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
                    }
                }
                // share: export this theme, import ones from Documents/FreeForm Themes
                Flow {
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
                Rectangle {
                    id: app
                    readonly property var t: root.draft
                    x: 28; y: 48; width: parent.width - 56; height: parent.height - 76
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
