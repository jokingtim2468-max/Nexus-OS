// Widget Studio — make your own desktop widgets: a mini media player, a clock, a launcher bar…
//
//   qs -c MacShell ipc call widgetstudio open | close | toggle
//
// Build a widget from blocks (text with live {tokens}, buttons with premade actions, album art,
// progress bars, images, shapes), then "Show on Desktop": it sits on the desktop below your
// windows and can be dragged there. Everything is saved to ~/.config/macshell/custom-widgets.json.
// Rendering: WidgetView.qml, live data + actions: WidgetContext.qml.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string home: Quickshell.env("HOME") || Quickshell.env("USERPROFILE")

    property var widgets: []          // saved widgets
    property int current: -1          // the one being edited
    property int sel: -1              // its selected item
    property bool loaded: false
    readonly property var cw: current >= 0 && current < widgets.length ? widgets[current] : null
    readonly property var ci: cw && sel >= 0 && sel < cw.items.length ? cw.items[sel] : null

    WidgetContext { id: wctx; hub: root.hub }

    function open() { win.visible = true; win.raise(); win.requestActivate(); if (widgets.length === 0) addFromTemplate(0); else if (current < 0) current = 0; }
    function close() { win.visible = false; }
    function toggle() { if (win.visible) close(); else open(); }

    // ── templates ──
    readonly property var templates: [
        { name: "Mini Player", w: 340, h: 112, bg: { color: "#1C1C1E", opacity: 0.86, radius: 24, border: true }, items: [
            { type: "art", x: 14, y: 14, w: 84, h: 84, radius: 14 },
            { type: "text", x: 112, y: 16, w: 214, h: 22, text: "{title}", size: 15, bold: true, color: "#FFFFFF" },
            { type: "text", x: 112, y: 38, w: 214, h: 18, text: "{artist}", size: 13, color: "#B0B0B5" },
            { type: "progress", x: 112, y: 60, w: 210, h: 8, source: "media", color: "#FFFFFF" },
            { type: "button", x: 136, y: 72, w: 34, h: 34, action: "media.previous", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 196, y: 70, w: 38, h: 38, action: "media.toggle", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 260, y: 72, w: 34, h: 34, action: "media.next", icon: "auto", color: "#FFFFFF" } ] },
        { name: "Clock", w: 220, h: 110, bg: { color: "#1C1C1E", opacity: 0.8, radius: 24, border: true }, items: [
            { type: "text", x: 18, y: 14, w: 184, h: 20, text: "{day}", size: 14, bold: true, color: "#FF453A" },
            { type: "text", x: 18, y: 36, w: 184, h: 44, text: "{time}", size: 36, bold: true, color: "#FFFFFF" },
            { type: "text", x: 18, y: 80, w: 184, h: 18, text: "{date}", size: 13, color: "#B0B0B5" } ] },
        { name: "Battery & Volume", w: 260, h: 100, bg: { color: "#1C1C1E", opacity: 0.8, radius: 22, border: true }, items: [
            { type: "text", x: 18, y: 12, w: 140, h: 20, text: "Battery {battery}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 34, w: 224, h: 8, source: "battery", color: "#30D158" },
            { type: "text", x: 18, y: 52, w: 140, h: 20, text: "Volume {volume}", size: 13, bold: true, color: "#FFFFFF" },
            { type: "progress", x: 18, y: 74, w: 160, h: 8, source: "volume", color: "#0A84FF" },
            { type: "button", x: 190, y: 62, w: 28, h: 28, action: "volume.down", icon: "auto", color: "#FFFFFF" },
            { type: "button", x: 218, y: 62, w: 28, h: 28, action: "volume.up", icon: "auto", color: "#FFFFFF" } ] },
        { name: "Blank", w: 260, h: 140, bg: { color: "#1C1C1E", opacity: 0.85, radius: 22, border: true }, items: [] }
    ]

    function clone(o) { return JSON.parse(JSON.stringify(o)); }
    function commit(list) { widgets = list; saveTimer.restart(); }
    function addFromTemplate(i) {
        var w = clone(templates[i]);
        w.id = Date.now().toString(36); w.onDesktop = false; w.x = 80 + widgets.length * 30; w.y = 120 + widgets.length * 30;
        var l = widgets.slice(); l.push(w); commit(l); current = l.length - 1; sel = -1;
    }
    function updateWidget(fields) {
        if (!cw) return;
        var l = widgets.slice(), w = clone(cw);
        for (var k in fields) w[k] = fields[k];
        l[current] = w; commit(l);
    }
    function updateItem(fields) {
        if (!ci) return;
        var w = clone(cw);
        for (var k in fields) w.items[sel][k] = fields[k];
        var l = widgets.slice(); l[current] = w; commit(l);
    }
    function addItem(type) {
        if (!cw) return;
        var base = { text: { type: "text", w: 160, h: 24, text: "{title}", size: 15, color: "#FFFFFF" },
                     button: { type: "button", w: 36, h: 36, action: "media.toggle", icon: "auto", color: "#FFFFFF" },
                     art: { type: "art", w: 72, h: 72, radius: 12 },
                     progress: { type: "progress", w: 160, h: 8, source: "media", color: "#FFFFFF" },
                     image: { type: "image", w: 80, h: 80, src: "", radius: 12 },
                     shape: { type: "shape", w: 80, h: 40, color: "#0A84FF", radius: 10, opacity: 1 } }[type];
        var w = clone(cw); var it = clone(base); it.x = 16; it.y = 16;
        w.items.push(it); var l = widgets.slice(); l[current] = w; commit(l); sel = w.items.length - 1;
    }
    function deleteItem() {
        if (!ci) return;
        var w = clone(cw); w.items.splice(sel, 1); var l = widgets.slice(); l[current] = w; commit(l); sel = -1;
    }
    function deleteWidget() {
        if (!cw) return;
        var l = widgets.slice(); l.splice(current, 1); commit(l); current = Math.min(current, l.length - 1); sel = -1;
    }
    function moveDesktop(index, x, y) {
        var l = widgets.slice(), w = clone(l[index]); w.x = Math.round(x); w.y = Math.round(y); l[index] = w; commit(l);
    }

    // ── saving ──
    FileView {
        id: store
        path: root.home + "/.config/macshell/custom-widgets.json"
        printErrors: false
        onLoaded: { try { root.widgets = JSON.parse(text()).widgets || []; } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
    Timer { id: saveTimer; interval: 400; onTriggered: store.setText(JSON.stringify({ widgets: root.widgets }, null, 1)) }

    // ═════════════ ON THE DESKTOP ═════════════
    Variants {
        model: root.widgets.map(function (w, i) { return { w: w, i: i }; }).filter(function (e) { return e.w.onDesktop; })
        PanelWindow {
            id: dw
            required property var modelData
            readonly property var w: modelData.w
            property real dragX: 0
            property real dragY: 0
            screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
            anchors { top: true; left: true }
            margins { left: Math.max(0, (dw.w.x || 0) + dragX); top: Math.max(0, (dw.w.y || 0) + dragY) }
            implicitWidth: dw.w.w; implicitHeight: dw.w.h
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "freeform-widget"
            WidgetView { widget: dw.w; ctx: wctx; fam: root.fam }
            // drag anywhere that isn't a control to move it; saved when let go
            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton
                onTranslationChanged: { dw.dragX = translation.x; dw.dragY = translation.y; }
                onActiveChanged: if (!active) { root.moveDesktop(dw.modelData.i, (dw.w.x || 0) + dw.dragX, (dw.w.y || 0) + dw.dragY); dw.dragX = 0; dw.dragY = 0; }
            }
        }
    }

    // ═════════════ THE EDITOR ═════════════
    Window {
        id: win
        title: "Widget Studio"
        width: 1120; height: 700
        minimumWidth: 900; minimumHeight: 560
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property color bg: dark ? "#1E1E1E" : "#FFFFFF"
            readonly property color side: dark ? "#2A2A2C" : "#F0F0F2"
            readonly property color canvas: dark ? "#141416" : "#E5E5EA"
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color sel: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
        }

        // small building blocks of the inspector
        component Label: Text { color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
        component Field: Rectangle {
            id: fld
            property alias text: ti.text
            signal edited(string text)
            width: parent ? parent.width : 200; height: 28; radius: 7; color: pal.field
            TextInput {
                id: ti
                x: 8; width: parent.width - 16; anchors.verticalCenter: parent.verticalCenter
                color: pal.text; font.family: root.fam; font.pixelSize: 13; clip: true; selectByMouse: true
                onTextEdited: fld.edited(text)
            }
        }
        component Chip: Rectangle {
            id: ch
            property string label: ""
            property bool on: false
            signal clicked()
            width: cht.implicitWidth + 18; height: 26; radius: 13
            color: on ? root.accent : pal.field
            Text { id: cht; anchors.centerIn: parent; text: ch.label; color: ch.on ? "white" : pal.text; font.family: root.fam; font.pixelSize: 12 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
        }
        component Stepper: Row {
            id: st
            property string label: ""
            property int value: 0
            property int step: 1
            signal changed(int v)
            spacing: 6
            Text { width: 26; anchors.verticalCenter: parent.verticalCenter; text: st.label; color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
            Rectangle {
                width: 26; height: 26; radius: 7; color: pal.field
                Text { anchors.centerIn: parent; text: "−"; color: pal.text }
                MouseArea { anchors.fill: parent; onClicked: st.changed(st.value - st.step) }
            }
            Text { width: 34; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: st.value; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
            Rectangle {
                width: 26; height: 26; radius: 7; color: pal.field
                Text { anchors.centerIn: parent; text: "+"; color: pal.text }
                MouseArea { anchors.fill: parent; onClicked: st.changed(st.value + st.step) }
            }
        }
        readonly property var swatches: ["#FFFFFF", "#B0B0B5", "#1C1C1E", "#000000", "#0A84FF", "#30D158", "#FFD60A", "#FF9F0A", "#FF453A", "#FF375F", "#BF5AF2", "#64D2FF"]
        component Swatches: Flow {
            id: sw
            property string value: ""
            signal changed(string c)
            width: parent ? parent.width : 200; spacing: 6
            Repeater {
                model: win.swatches
                delegate: Rectangle {
                    required property string modelData
                    width: 22; height: 22; radius: 11; color: modelData
                    border.width: sw.value.toUpperCase() === modelData ? 3 : 1
                    border.color: sw.value.toUpperCase() === modelData ? root.accent : pal.border
                    MouseArea { anchors.fill: parent; onClicked: sw.changed(parent.modelData) }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12; color: pal.bg
            border.width: 1; border.color: pal.border
            clip: true

            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // ── left: my widgets + templates ──
            Rectangle {
                id: side
                width: 220; height: parent.height; color: pal.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Row {
                    x: 18; y: 18; spacing: 8
                    Repeater {
                        model: ["#FF5F57", "#FEBC2E", "#28C840"]
                        delegate: Rectangle { required property string modelData; required property int index; width: 14; height: 14; radius: 7; color: index !== 1 && win.active ? modelData : pal.lightOff; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14) }
                    }
                }
                MouseArea { x: 16; y: 16; width: 20; height: 18; onClicked: win.visible = false }
                Column {
                    x: 10; y: 52; width: parent.width - 20; spacing: 2
                    Label { leftPadding: 8; text: I18n.tr("MY WIDGETS") }
                    Repeater {
                        model: root.widgets
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 32; radius: 7
                            color: root.current === index ? pal.sel : "transparent"
                            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40; elide: Text.ElideRight; text: parent.modelData.name; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                            Rectangle { visible: parent.modelData.onDesktop; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 4; color: "#30D158" }
                            MouseArea { anchors.fill: parent; onClicked: { root.current = parent.index; root.sel = -1; } }
                        }
                    }
                    Item { width: 1; height: 12 }
                    Label { leftPadding: 8; text: I18n.tr("NEW FROM TEMPLATE") }
                    Repeater {
                        model: root.templates
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 30; radius: 7
                            color: tma.containsMouse ? pal.sel : "transparent"
                            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "+  " + parent.modelData.name; color: root.accent; font.family: root.fam; font.pixelSize: 13 }
                            MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; onClicked: root.addFromTemplate(parent.index) }
                        }
                    }
                }
            }

            // ── centre: toolbar + canvas ──
            Item {
                id: centre
                x: side.width; width: parent.width - side.width - inspector.width; height: parent.height
                Rectangle {
                    id: toolbar
                    width: parent.width; height: 52; color: pal.bg
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                    DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                    Row {
                        x: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Repeater {
                            model: [{ t: "text", l: "Text" }, { t: "button", l: "Button" }, { t: "art", l: "Album Art" }, { t: "progress", l: "Progress" }, { t: "image", l: "Image" }, { t: "shape", l: "Shape" }]
                            delegate: Chip { required property var modelData; label: "+ " + I18n.tr(modelData.l); onClicked: root.addItem(modelData.t) }
                        }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Chip {
                            visible: !!root.cw
                            label: root.cw && root.cw.onDesktop ? I18n.tr("On Desktop ✓") : I18n.tr("Show on Desktop")
                            on: !!(root.cw && root.cw.onDesktop)
                            onClicked: root.updateWidget({ onDesktop: !root.cw.onDesktop })
                        }
                    }
                }
                Rectangle {
                    id: canvas
                    y: toolbar.height; width: parent.width; height: parent.height - toolbar.height
                    color: pal.canvas
                    // dotted grid
                    Canvas {
                        anchors.fill: parent
                        onPaint: { var c = getContext("2d"); c.fillStyle = pal.dark ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.08)"; for (var x = 10; x < width; x += 20) for (var y = 10; y < height; y += 20) c.fillRect(x, y, 2, 2); }
                    }
                    MouseArea { anchors.fill: parent; onPressed: root.sel = -1 }
                    Text {
                        visible: !root.cw
                        anchors.centerIn: parent
                        text: I18n.tr("Pick a template on the left to start")
                        color: pal.text2; font.family: root.fam; font.pixelSize: 15
                    }
                    Item {
                        id: stage
                        visible: !!root.cw
                        readonly property real sc: root.cw ? Math.min(2, (canvas.width - 80) / root.cw.w, (canvas.height - 80) / root.cw.h) : 1
                        width: root.cw ? root.cw.w : 0; height: root.cw ? root.cw.h : 0
                        anchors.centerIn: parent
                        scale: sc
                        WidgetView {
                            id: preview
                            widget: root.cw || ({ w: 10, h: 10, items: [] })
                            ctx: wctx; fam: root.fam
                            editing: true; selected: root.sel
                            onPicked: i => root.sel = i
                        }
                        // drag the selected item; corner handle resizes it
                        Item {
                            visible: !!root.ci
                            x: root.ci ? root.ci.x : 0; y: root.ci ? root.ci.y : 0
                            width: root.ci ? root.ci.w : 0; height: root.ci ? root.ci.h : 0
                            property real ox: 0
                            property real oy: 0
                            DragHandler {
                                target: null
                                onActiveChanged: if (active) { parent.ox = root.ci.x; parent.oy = root.ci.y; }
                                onTranslationChanged: if (active && root.ci) root.updateItem({ x: Math.round(parent.ox + translation.x / stage.sc), y: Math.round(parent.oy + translation.y / stage.sc) })
                            }
                            Rectangle {
                                x: parent.width - 6; y: parent.height - 6; width: 12; height: 12; radius: 6
                                color: "white"; border.width: 2; border.color: root.accent
                                property real ow: 0
                                property real oh: 0
                                DragHandler {
                                    target: null
                                    onActiveChanged: if (active) { parent.ow = root.ci.w; parent.oh = root.ci.h; }
                                    onTranslationChanged: if (active && root.ci) root.updateItem({ w: Math.max(8, Math.round(parent.ow + translation.x / stage.sc)), h: Math.max(4, Math.round(parent.oh + translation.y / stage.sc)) })
                                }
                            }
                        }
                    }
                }
            }

            // ── right: inspector ──
            Rectangle {
                id: inspector
                anchors.right: parent.right
                width: 280; height: parent.height; color: pal.side
                Rectangle { width: 1; height: parent.height; color: pal.sep }
                Flickable {
                    anchors.fill: parent; anchors.margins: 16
                    contentHeight: insp.height; clip: true
                    Column {
                        id: insp
                        width: parent.width; spacing: 8
                        visible: !!root.cw

                        // the selected item
                        Column {
                            visible: !!root.ci
                            width: parent.width; spacing: 8
                            Text { text: root.ci ? I18n.tr({ text: "Text", button: "Button", art: "Album Art", progress: "Progress Bar", image: "Image", shape: "Shape" }[root.ci.type]) : ""; color: pal.text; font.family: root.fam; font.pixelSize: 17; font.weight: Font.Bold }
                            Grid {
                                columns: 2; spacing: 6
                                Stepper { label: "X"; value: root.ci ? root.ci.x : 0; onChanged: v => root.updateItem({ x: v }) }
                                Stepper { label: "Y"; value: root.ci ? root.ci.y : 0; onChanged: v => root.updateItem({ y: v }) }
                                Stepper { label: "W"; value: root.ci ? root.ci.w : 0; onChanged: v => root.updateItem({ w: Math.max(4, v) }) }
                                Stepper { label: "H"; value: root.ci ? root.ci.h : 0; onChanged: v => root.updateItem({ h: Math.max(4, v) }) }
                            }
                            // text
                            Label { visible: root.ci && (root.ci.type === "text" || root.ci.type === "button"); text: root.ci && root.ci.type === "button" ? I18n.tr("LABEL (optional)") : I18n.tr("TEXT") }
                            Field {
                                visible: root.ci && (root.ci.type === "text" || root.ci.type === "button")
                                text: root.ci ? (root.ci.type === "button" ? root.ci.label || "" : root.ci.text || "") : ""
                                onEdited: t => root.updateItem(root.ci.type === "button" ? { label: t } : { text: t })
                            }
                            Flow {
                                visible: root.ci && root.ci.type === "text"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: wctx.tokens
                                    delegate: Chip { required property string modelData; label: "{" + modelData + "}"; onClicked: root.updateItem({ text: (root.ci.text || "") + "{" + modelData + "}" }) }
                                }
                            }
                            Row {
                                visible: root.ci && (root.ci.type === "text" || root.ci.type === "button")
                                spacing: 6
                                Stepper { label: I18n.tr("Size"); value: root.ci ? root.ci.size || 14 : 14; onChanged: v => root.updateItem({ size: Math.max(6, v) }) }
                                Chip { visible: root.ci && root.ci.type === "text"; label: "B"; on: !!(root.ci && root.ci.bold); onClicked: root.updateItem({ bold: !root.ci.bold }) }
                            }
                            Row {
                                visible: root.ci && root.ci.type === "text"
                                spacing: 4
                                Repeater {
                                    model: ["left", "center", "right"]
                                    delegate: Chip { required property string modelData; label: I18n.tr(modelData); on: root.ci && (root.ci.align || "left") === modelData; onClicked: root.updateItem({ align: modelData }) }
                                }
                            }
                            // button action
                            Label { visible: root.ci && root.ci.type === "button"; text: I18n.tr("WHEN CLICKED") }
                            Flow {
                                visible: root.ci && root.ci.type === "button"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: wctx.actions
                                    delegate: Chip { required property var modelData; label: I18n.tr(modelData.label); on: root.ci && root.ci.action === modelData.id; onClicked: root.updateItem({ action: modelData.id }) }
                                }
                            }
                            Label { visible: root.ci && (root.ci.action === "open.app" || root.ci.action === "open.url"); text: root.ci && root.ci.action === "open.url" ? I18n.tr("WEBSITE") : I18n.tr("APP OR COMMAND") }
                            Field {
                                visible: root.ci && (root.ci.action === "open.app" || root.ci.action === "open.url")
                                text: root.ci ? root.ci.param || "" : ""
                                onEdited: t => root.updateItem({ param: t })
                            }
                            Label { visible: root.ci && root.ci.type === "button"; text: I18n.tr("ICON") }
                            Flow {
                                visible: root.ci && root.ci.type === "button"
                                width: parent.width; spacing: 4
                                Repeater {
                                    model: ["auto", "play", "pause", "next", "prev", "shuffle", "repeat", "volume", "speaker", "note", "appstore", "gear", "search", "folder", "link", "power", "moon", "sun", "none"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 30; height: 30; radius: 7
                                        color: root.ci && (root.ci.icon || "auto") === modelData ? root.accent : pal.field
                                        WGlyph { visible: parent.modelData !== "auto" && parent.modelData !== "none"; anchors.centerIn: parent; width: 15; height: 15; kind: parent.modelData; color: pal.text }
                                        Text { visible: parent.modelData === "auto" || parent.modelData === "none"; anchors.centerIn: parent; text: parent.modelData === "auto" ? "A" : "—"; color: pal.text; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; onClicked: root.updateItem({ icon: parent.modelData }) }
                                    }
                                }
                            }
                            // progress source
                            Label { visible: root.ci && root.ci.type === "progress"; text: I18n.tr("SHOWS") }
                            Row {
                                visible: root.ci && root.ci.type === "progress"
                                spacing: 4
                                Repeater {
                                    model: [{ v: "media", l: "Song" }, { v: "volume", l: "Volume" }, { v: "battery", l: "Battery" }]
                                    delegate: Chip { required property var modelData; label: I18n.tr(modelData.l); on: root.ci && (root.ci.source || "media") === modelData.v; onClicked: root.updateItem({ source: modelData.v }) }
                                }
                            }
                            // image
                            Label { visible: root.ci && root.ci.type === "image"; text: I18n.tr("IMAGE FILE OR LINK") }
                            Field { visible: root.ci && root.ci.type === "image"; text: root.ci ? root.ci.src || "" : ""; onEdited: t => root.updateItem({ src: t }) }
                            // radius
                            Stepper {
                                visible: root.ci && (root.ci.type === "art" || root.ci.type === "image" || root.ci.type === "shape")
                                label: I18n.tr("Round"); value: root.ci ? root.ci.radius || 0 : 0
                                onChanged: v => root.updateItem({ radius: Math.max(0, v) })
                            }
                            // colour
                            Label { visible: root.ci && root.ci.type !== "art" && root.ci.type !== "image"; text: I18n.tr("COLOUR") }
                            Swatches { visible: root.ci && root.ci.type !== "art" && root.ci.type !== "image"; value: root.ci ? root.ci.color || "#FFFFFF" : ""; onChanged: c => root.updateItem({ color: c }) }
                            Row {
                                spacing: 6
                                Chip { label: I18n.tr("Bring Forward"); onClicked: { var w = root.clone(root.cw), it = w.items.splice(root.sel, 1)[0]; w.items.push(it); var l = root.widgets.slice(); l[root.current] = w; root.commit(l); root.sel = w.items.length - 1; } }
                                Chip { label: I18n.tr("Delete"); onClicked: root.deleteItem() }
                            }
                            Rectangle { width: parent.width; height: 1; color: pal.sep }
                        }

                        // the widget itself
                        Text { text: I18n.tr("Widget"); color: pal.text; font.family: root.fam; font.pixelSize: 17; font.weight: Font.Bold }
                        Label { text: I18n.tr("NAME") }
                        Field { text: root.cw ? root.cw.name : ""; onEdited: t => root.updateWidget({ name: t }) }
                        Grid {
                            columns: 2; spacing: 6
                            Stepper { label: "W"; step: 10; value: root.cw ? root.cw.w : 0; onChanged: v => root.updateWidget({ w: Math.max(60, v) }) }
                            Stepper { label: "H"; step: 10; value: root.cw ? root.cw.h : 0; onChanged: v => root.updateWidget({ h: Math.max(30, v) }) }
                        }
                        Label { text: I18n.tr("BACKGROUND") }
                        Swatches {
                            value: root.cw && root.cw.bg ? root.cw.bg.color : ""
                            onChanged: c => { var b = root.clone(root.cw.bg || {}); b.color = c; root.updateWidget({ bg: b }); }
                        }
                        Row {
                            spacing: 6
                            Stepper { label: I18n.tr("Clear"); step: 10; value: root.cw && root.cw.bg ? Math.round((1 - root.cw.bg.opacity) * 100) : 0
                                onChanged: v => { var b = root.clone(root.cw.bg || {}); b.opacity = Math.max(0, Math.min(1, 1 - v / 100)); root.updateWidget({ bg: b }); } }
                        }
                        Stepper { label: I18n.tr("Round"); step: 2; value: root.cw && root.cw.bg ? root.cw.bg.radius : 0
                            onChanged: v => { var b = root.clone(root.cw.bg || {}); b.radius = Math.max(0, v); root.updateWidget({ bg: b }); } }
                        Item { width: 1; height: 6 }
                        Chip { label: I18n.tr("Delete Widget"); onClicked: root.deleteWidget() }
                    }
                }
            }
        }
    }
}
