// App Store — the macOS App Store for MacShell: Discover, categories, search, updates, installed apps.
//
//   qs -c MacShell ipc call appstore open | close | toggle | page updates | search firefox
//
// Installs real apps: on Windows through winget (built into Windows 10/11; its "msstore" source is the
// Microsoft Store), on Linux through Flatpak. The work is done by `macshell-helper store ...`
// (compat/helper/store.py); this file is only the UI. The Discover / category pages come from
// assets/appstore/featured.json, everything else from live searches.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property bool windows: Qt.platform.os === "windows"
    readonly property string sourceName: windows ? I18n.tr("Microsoft Store & winget") : "Flathub"

    // ═════════════ STATE ═════════════
    property string page: "discover"        // discover | essentials | create | work | play | develop | privacy | search | updates | installed
    property string query: ""
    property var featured: ({ hero: { apps: [] }, sections: [], apps: [] })
    property var installed: ({})             // id -> { version, available }
    property var installedList: []
    property var updates: []
    property var results: []
    property bool searching: false
    property bool listing: false
    property var busy: ({})                  // id -> "install" | "update" | "uninstall"
    property var queue: []
    property string errorText: ""

    readonly property var pages: [
        { id: "discover", t: "Discover", g: "appstore" },
        { id: "essentials", t: "Essentials", g: "folder" },
        { id: "create", t: "Create", g: "photo" },
        { id: "work", t: "Work", g: "doc" },
        { id: "play", t: "Play", g: "play" },
        { id: "develop", t: "Develop", g: "keyboard" },
        { id: "privacy", t: "Privacy & Security", g: "lock" },
        { id: "updates", t: "Updates", g: "restart" },
        { id: "installed", t: "Installed", g: "check" }
    ]

    function open(p) {
        if (p) root.page = p;
        refresh();
        win.visible = true; win.raise(); win.requestActivate();
    }
    function close() { win.visible = false; }
    function toggle() { if (win.visible) close(); else open(); }
    function search(q) {
        if (searchInput.text !== q) searchInput.text = q;
        root.query = q;
        root.page = q.trim() === "" ? "discover" : "search";
        if (q.trim() !== "") searchDelay.restart();
    }

    // featured.json app -> the shape the rows use; null when this platform has no package for it
    function fromFeatured(a) {
        if (!a) return null;
        if (!windows && !a.flat) return null;
        return { id: windows ? a.id : a.flat, src: windows ? a.src : "flathub", name: a.name, sub: a.sub,
                 icon: a.icon, c1: a.c1, c2: a.c2 };
    }
    function featuredById(id) {
        var l = featured.apps || [];
        for (var i = 0; i < l.length; i++) if (l[i].id === id || l[i].flat === id) return l[i];
        return null;
    }
    function appsIn(cat) {
        var out = [], l = featured.apps || [];
        for (var i = 0; i < l.length; i++) if (l[i].cat === cat) { var a = fromFeatured(l[i]); if (a) out.push(a); }
        return out;
    }
    // a store row (search / list output) dressed with the featured artwork when we have it
    function decorate(a) {
        var f = featuredById(a.id);
        return { id: a.id, src: a.source, name: f ? f.name : a.name, sub: f ? f.sub : (a.source === "msstore" ? "Microsoft Store" : a.source),
                 icon: f ? f.icon : "", c1: f ? f.c1 : "", c2: f ? f.c2 : "", version: a.version, available: a.available };
    }
    function parseApps(text) {
        var out = [], lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].replace(/\r$/, "");
            if (l.indexOf("A:") !== 0) continue;
            var f = l.substring(2).split("\t");
            if (f.length < 5 || !f[0]) continue;
            out.push({ id: f[0], name: f[1], version: f[2], available: f[3], source: f[4] });
        }
        return out;
    }
    function stateOf(id) {
        if (busy[id]) return busy[id];
        var i = installed[id];
        if (!i) return "get";
        return i.available ? "updatable" : "installed";
    }

    // ═════════════ BACKEND ═════════════
    function refresh() { if (!listProc.running) { root.listing = true; listProc.running = true; } }
    Process {
        id: listProc
        command: ["macshell-helper", "store", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var apps = root.parseApps(text), map = {}, ups = [], all = [];
                for (var i = 0; i < apps.length; i++) {
                    map[apps[i].id] = { version: apps[i].version, available: apps[i].available };
                    var d = root.decorate(apps[i]);
                    all.push(d);
                    if (apps[i].available) ups.push(d);
                }
                all.sort(function (a, b) { return a.name.localeCompare(b.name); });
                root.installed = map; root.installedList = all; root.updates = ups;
                root.listing = false;
            }
        }
    }

    Timer { id: searchDelay; interval: 400; onTriggered: root.runSearch() }
    function runSearch() {
        if (root.query.trim() === "") return;
        if (searchProc.running) { searchDelay.restart(); return; }
        root.searching = true;
        searchProc.command = ["macshell-helper", "store", "search", root.query.trim()];
        searchProc.running = true;
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                var apps = root.parseApps(text), out = [];
                for (var i = 0; i < apps.length && out.length < 60; i++) out.push(root.decorate(apps[i]));
                root.results = out;
                root.searching = false;
            }
        }
    }

    // install / update / uninstall run one at a time, in the order they were asked for
    function act(kind, app) {
        if (busy[app.id]) return;
        var b = Object.assign({}, busy); b[app.id] = kind; busy = b;
        queue = queue.concat([{ kind: kind, id: app.id, src: app.src || "", name: app.name }]);
        runNext();
    }
    function updateAll() { for (var i = 0; i < updates.length; i++) act("update", updates[i]); }
    function runNext() {
        if (actionProc.running || queue.length === 0) return;
        var job = queue[0];
        actionProc.job = job;
        actionProc.command = job.kind === "install" ? ["macshell-helper", "store", "install", job.id, job.src]
                                                    : ["macshell-helper", "store", job.kind, job.id];
        actionProc.running = true;
    }
    Process {
        id: actionProc
        property var job: null
        stderr: StdioCollector { id: actionErr }
        onExited: (code, status) => {
            var job = actionProc.job;
            if (code !== 0 && job) {
                var msg = actionErr.text.trim().split("\n").pop();
                root.errorText = (job.kind === "install" ? I18n.tr("Couldn't install ") : job.kind === "update" ? I18n.tr("Couldn't update ") : I18n.tr("Couldn't remove "))
                                 + job.name + (msg ? ": " + msg : ".");
                errorHide.restart();
            }
            var b = Object.assign({}, root.busy); if (job) delete b[job.id]; root.busy = b;
            root.queue = root.queue.slice(1);
            root.refresh();
            root.runNext();
        }
    }
    Timer { id: errorHide; interval: 8000; onTriggered: root.errorText = "" }

    FileView {
        path: {
            var s = decodeURIComponent(Qt.resolvedUrl("assets/appstore/featured.json").toString().replace(/^file:\/\//, ""));
            return /^\/[A-Za-z]:/.test(s) ? s.substring(1) : s;          // file:///C:/... on Windows
        }
        onLoaded: { try { root.featured = JSON.parse(text()); } catch (e) { console.warn("featured.json:", e); } }
    }

    // ═════════════ UI PIECES ═════════════
    // An app icon: the icon theme's when it has one, else a tile in the app's colours with its initial.
    component AppIcon: Item {
        id: ai
        property var app: ({})
        property real size: 56
        width: size; height: size
        readonly property string themed: app && app.icon ? Quickshell.iconPath(app.icon, true) : ""
        Image {
            anchors.fill: parent
            visible: ai.themed !== "" && status === Image.Ready
            source: ai.themed
            sourceSize: Qt.size(ai.size * 2, ai.size * 2)
            smooth: true; mipmap: true
        }
        Rectangle {
            anchors.fill: parent
            visible: ai.themed === ""
            radius: ai.size * 0.225
            gradient: Gradient {
                GradientStop { position: 0; color: ai.app && ai.app.c1 ? ai.app.c1 : "#8E8E93" }
                GradientStop { position: 1; color: ai.app && ai.app.c2 ? ai.app.c2 : "#48484A" }
            }
            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.12)
            Text {
                anchors.centerIn: parent
                text: ai.app && ai.app.name ? ai.app.name.charAt(0).toUpperCase() : "?"
                color: ai.app && ai.app.c1 === "#FFFFFF" ? "#111111" : "white"
                font.pixelSize: ai.size * 0.46; font.weight: Font.Bold
            }
        }
    }

    // The capsule button: Get / Update / Installed / Uninstall, with a spinner while working.
    component Pill: Item {
        id: pl
        property var st: null
        property var p: null
        property var app: ({})
        property bool removeMode: false
        property bool onColor: false          // on the coloured Discover banner: white capsule
        readonly property string state: st ? st.stateOf(app.id) : "get"
        readonly property bool working: state === "install" || state === "update" || state === "uninstall"
        readonly property string label: removeMode ? I18n.tr("Uninstall")
                                       : state === "updatable" ? I18n.tr("Update")
                                       : state === "installed" ? I18n.tr("Installed") : I18n.tr("Get")
        width: working ? 28 : lbl.implicitWidth + 30; height: 28
        Rectangle {
            visible: !pl.working
            anchors.fill: parent; radius: 14
            color: pl.state === "installed" && !pl.removeMode ? "transparent"
                 : pl.onColor ? Qt.rgba(1, 1, 1, pma.pressed ? 0.45 : 0.3) : (pma.pressed ? pl.p.pillDown : pl.p.pill)
            Text {
                id: lbl
                anchors.centerIn: parent
                text: pl.label
                color: pl.removeMode ? "#FF453A" : pl.onColor ? "white" : (pl.state === "installed" ? pl.p.text2 : pl.st.accent)
                font.family: pl.st.fam; font.pixelSize: 13; font.weight: Font.Bold
            }
            MouseArea {
                id: pma
                anchors.fill: parent
                enabled: pl.removeMode || pl.state !== "installed"
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: pl.st.act(pl.removeMode ? "uninstall" : (pl.state === "updatable" ? "update" : "install"), pl.app)
            }
        }
        // spinner (the App Store's progress ring, indeterminate: winget doesn't report progress)
        Canvas {
            id: spin
            visible: pl.working
            anchors.fill: parent
            property real a: 0
            NumberAnimation on a { running: pl.working; from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite }
            onAChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.lineWidth = 2.5; ctx.lineCap = "round";
                ctx.strokeStyle = pl.p.pill;
                ctx.beginPath(); ctx.arc(14, 14, 11, 0, Math.PI * 2); ctx.stroke();
                ctx.strokeStyle = pl.st.accent;
                ctx.beginPath(); ctx.arc(14, 14, 11, a, a + 1.6); ctx.stroke();
            }
        }
    }

    // One app in a list: icon, name, one-line description, the capsule.
    component AppRow: Item {
        id: ar
        property var st: null
        property var p: null
        property var app: ({})
        property bool removeMode: false
        property bool lastRow: false
        height: 78
        AppIcon { id: ic; app: ar.app; size: 56; anchors.verticalCenter: parent.verticalCenter }
        Column {
            x: 72; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 72 - pill.width - 16
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: ar.app.name || ar.app.id; color: ar.p.text; font.family: ar.st.fam; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: ar.app.available && !ar.removeMode ? I18n.tr("Version ") + ar.app.available + " \u00b7 " + (ar.app.sub || "") : (ar.app.sub || "")
                color: ar.p.text2; font.family: ar.st.fam; font.pixelSize: 12
            }
        }
        Pill { id: pill; st: ar.st; p: ar.p; app: ar.app; removeMode: ar.removeMode; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
        Rectangle { visible: !ar.lastRow; x: 72; anchors.bottom: parent.bottom; width: parent.width - 72; height: 1; color: ar.p.sep }
    }

    // ═════════════ THE WINDOW ═════════════
    Window {
        id: win
        title: "App Store"
        width: 1080; height: 720
        minimumWidth: 860; minimumHeight: 560
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            // a FreeForm theme preset (Settings > Appearance > Theme) recolours the window
            readonly property var preset: root.dock && root.dock.themePreset && root.dock.themePreset !== "default"
                                          ? root.dock.themePresets.filter(function (t) { return t.id === root.dock.themePreset; })[0] : null
            readonly property color bg: preset ? preset.bg : (dark ? "#1E1E1E" : "#FFFFFF")
            readonly property color side: preset ? preset.card : (dark ? "#2A2A2C" : "#F0F0F2")
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color sel: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
            readonly property color pill: dark ? Qt.rgba(1, 1, 1, 0.13) : "#EEEEF0"
            readonly property color pillDown: dark ? Qt.rgba(1, 1, 1, 0.22) : "#DCDCE0"
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
        }

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 12
            color: pal.bg
            border.width: 1; border.color: pal.border
            clip: true

            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }
            MouseArea { x: parent.width - 5; y: 10; width: 5; height: parent.height - 20; z: 100; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 10; y: parent.height - 5; width: parent.width - 20; height: 5; z: 100; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }

            // ── sidebar ──
            Rectangle {
                id: sidebar
                width: 236; height: parent.height
                color: pal.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

                // traffic lights
                Row {
                    x: 18; y: 18
                    spacing: 8
                    Repeater {
                        model: ["#FF5F57", "#FEBC2E", "#28C840"]
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: 14; height: 14; radius: 7
                            color: (index !== 1 && (win.active || tlMa.containsMouse)) ? modelData : pal.lightOff
                            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                        }
                    }
                }
                MouseArea {
                    id: tlMa
                    x: 16; y: 16; width: 62; height: 18; hoverEnabled: true
                    onClicked: mouse => {
                        if (mouse.x < 22) win.visible = false;
                        else if (mouse.x >= 44) win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized();
                    }
                }

                // search field
                Rectangle {
                    x: 14; y: 50; width: parent.width - 28; height: 30
                    radius: 8
                    color: pal.field
                    border.width: searchInput.activeFocus ? 2 : 0; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                    WGlyph { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; kind: "search"; color: pal.text2 }
                    TextInput {
                        id: searchInput
                        x: 30; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                        color: pal.text; font.family: root.fam; font.pixelSize: 13
                        selectByMouse: true; clip: true
                        onTextEdited: root.search(text)
                        Keys.onEscapePressed: { text = ""; root.search(""); }
                        Text { visible: !parent.text; text: I18n.tr("Search"); color: pal.text2; font: parent.font }
                    }
                }

                Column {
                    x: 10; y: 94; width: parent.width - 20
                    spacing: 2
                    Repeater {
                        model: root.pages
                        delegate: Rectangle {
                            id: navRow
                            required property var modelData
                            width: parent.width; height: 32; radius: 7
                            color: root.page === modelData.id ? pal.sel : (nma.containsMouse ? Qt.rgba(pal.sel.r, pal.sel.g, pal.sel.b, pal.sel.a * 0.5) : "transparent")
                            WGlyph { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; kind: navRow.modelData.g; color: root.accent }
                            Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(navRow.modelData.t); color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                            Rectangle {
                                readonly property int n: navRow.modelData.id === "updates" ? root.updates.length : 0
                                visible: n > 0
                                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(20, cnt.implicitWidth + 10); height: 18; radius: 9
                                color: root.accent
                                Text { id: cnt; anchors.centerIn: parent; text: parent.n; color: "white"; font.family: root.fam; font.pixelSize: 11; font.weight: Font.Bold }
                            }
                            MouseArea {
                                id: nma; anchors.fill: parent; hoverEnabled: true
                                onClicked: { root.page = navRow.modelData.id; searchInput.text = ""; root.query = ""; if (root.page === "updates" || root.page === "installed") root.refresh(); }
                            }
                        }
                    }
                }

                Text {
                    x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                    width: parent.width - 36; wrapMode: Text.WordWrap
                    text: I18n.tr("Apps from ") + root.sourceName
                    color: pal.text2; font.family: root.fam; font.pixelSize: 11
                }
            }

            // ── content ──
            Flickable {
                id: content
                x: sidebar.width; width: parent.width - sidebar.width; height: parent.height
                contentWidth: width; contentHeight: body.height + 60
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                DragHandler { target: null; acceptedDevices: PointerDevice.Mouse; onActiveChanged: if (active && content.contentY < 1 && centroid.position.y < 50) win.startSystemMove() }

                readonly property int cols: body.width > 1000 ? 3 : 2
                readonly property real cellW: Math.floor(body.width / cols)

                Column {
                    id: body
                    x: 36; y: 36; width: content.width - 72
                    spacing: 18

                    Text {
                        text: root.page === "search" ? I18n.tr("Results for \u201c") + root.query + "\u201d"
                              : I18n.tr((root.pages.filter(function (p) { return p.id === root.page; })[0] || { t: "" }).t)
                        color: pal.text; font.family: root.fam; font.pixelSize: 28; font.weight: Font.Bold
                    }

                    // ═══ Discover ═══
                    Rectangle {
                        visible: root.page === "discover"
                        width: parent.width; height: 230; radius: 16
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.darker(root.accent, 1.15) }
                            GradientStop { position: 1; color: "#AF52DE" }
                        }
                        Column {
                            x: 32; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.45
                            spacing: 8
                            Text { text: I18n.tr("FEATURED"); color: Qt.rgba(1, 1, 1, 0.75); font.family: root.fam; font.pixelSize: 12; font.weight: Font.Bold }
                            Text { width: parent.width; wrapMode: Text.WordWrap; text: I18n.tr(root.featured.hero ? root.featured.hero.title || "" : ""); color: "white"; font.family: root.fam; font.pixelSize: 30; font.weight: Font.Bold }
                            Text { width: parent.width; wrapMode: Text.WordWrap; text: I18n.tr(root.featured.hero ? root.featured.hero.sub || "" : ""); color: Qt.rgba(1, 1, 1, 0.85); font.family: root.fam; font.pixelSize: 15 }
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 32; anchors.verticalCenter: parent.verticalCenter
                            spacing: 14
                            Repeater {
                                model: (root.featured.hero ? root.featured.hero.apps || [] : []).map(function (id) { return root.fromFeatured(root.featuredById(id)); }).filter(function (a) { return a; })
                                delegate: Column {
                                    required property var modelData
                                    spacing: 8
                                    AppIcon { app: parent.modelData; size: 76; layer.enabled: true; layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.35; shadowVerticalOffset: 4 } }
                                    Pill { st: root; p: pal; app: parent.modelData; onColor: true; anchors.horizontalCenter: parent.horizontalCenter }
                                }
                            }
                        }
                    }

                    // Discover sections / a category page
                    Repeater {
                        model: root.page === "discover" ? (root.featured.sections || [])
                             : (["essentials", "create", "work", "play", "develop", "privacy"].indexOf(root.page) >= 0 ? [{ cat: root.page, title: "", all: true }] : [])
                        delegate: Column {
                            id: sec
                            required property var modelData
                            readonly property var apps: root.appsIn(modelData.cat)
                            width: body.width
                            spacing: 6
                            visible: apps.length > 0
                            Item {
                                visible: sec.modelData.title !== ""
                                width: parent.width; height: 30
                                Text { anchors.bottom: parent.bottom; text: I18n.tr(sec.modelData.title); color: pal.text; font.family: root.fam; font.pixelSize: 21; font.weight: Font.Bold }
                                Text {
                                    anchors.right: parent.right; anchors.bottom: parent.bottom
                                    text: I18n.tr("See All"); color: root.accent; font.family: root.fam; font.pixelSize: 13
                                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { root.page = sec.modelData.cat; content.contentY = 0; } }
                                }
                            }
                            Rectangle { visible: sec.modelData.title !== ""; width: parent.width; height: 1; color: pal.sep }
                            Flow {
                                width: parent.width
                                spacing: 0
                                Repeater {
                                    model: sec.modelData.all ? sec.apps : sec.apps.slice(0, content.cols * 2)
                                    delegate: Item {
                                        required property var modelData
                                        width: content.cellW; height: 78
                                        AppRow { width: content.cellW - 28; st: root; p: pal; app: parent.modelData }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ search / updates / installed lists ═══
                    Text {
                        visible: (root.page === "search" && (root.searching || root.results.length === 0))
                                 || (root.page === "updates" && root.updates.length === 0)
                                 || (root.page === "installed" && root.installedList.length === 0)
                        text: root.page === "search" ? (root.searching ? I18n.tr("Searching\u2026") : I18n.tr("No results"))
                              : root.listing ? I18n.tr("Checking\u2026")
                              : root.page === "updates" ? I18n.tr("All your apps are up to date.") : I18n.tr("No apps installed from the store yet.")
                        color: pal.text2; font.family: root.fam; font.pixelSize: 15
                    }
                    Item {
                        visible: root.page === "updates" && root.updates.length > 1
                        width: parent.width; height: 30
                        Rectangle {
                            anchors.right: parent.right
                            width: ua.implicitWidth + 30; height: 28; radius: 14; color: root.accent
                            Text { id: ua; anchors.centerIn: parent; text: I18n.tr("Update All"); color: "white"; font.family: root.fam; font.pixelSize: 13; font.weight: Font.Bold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.updateAll() }
                        }
                    }
                    Column {
                        width: parent.width
                        visible: ["search", "updates", "installed"].indexOf(root.page) >= 0
                        Repeater {
                            model: root.page === "search" ? (root.searching ? [] : root.results)
                                 : root.page === "updates" ? root.updates
                                 : root.page === "installed" ? root.installedList : []
                            delegate: AppRow {
                                required property var modelData
                                required property int index
                                width: body.width; st: root; p: pal; app: modelData
                                removeMode: root.page === "installed"
                            }
                        }
                    }
                }
            }

            // error banner
            Rectangle {
                visible: root.errorText !== ""
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                x: sidebar.width + (parent.width - sidebar.width - width) / 2
                width: Math.min(560, parent.width - sidebar.width - 40); height: errT.implicitHeight + 20; radius: 10
                color: pal.dark ? "#3A2222" : "#FFECEB"
                border.width: 1; border.color: Qt.rgba(1, 0.27, 0.23, 0.5)
                Text { id: errT; x: 14; width: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.WordWrap; text: root.errorText; color: pal.text; font.family: root.fam; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; onClicked: root.errorText = "" }
            }
        }
    }
}
