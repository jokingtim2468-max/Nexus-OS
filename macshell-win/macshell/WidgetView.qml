// WidgetView — draws one custom widget from its JSON description (Widget Studio).
// The same view is the live preview in the editor and the widget on the desktop.
//
// widget: { name, w, h, bg: { color, opacity, radius, border }, items: [ item… ] }
// item:   { type: "text" | "button" | "art" | "progress" | "image" | "shape", x, y, w, h, … }
//   text     text (with {tokens}), size, color, bold, align ("left"|"center"|"right")
//   button   action, param, icon ("auto" or a glyph), label, color, fill (background colour or "")
//   art      radius                      (the playing track's cover)
//   progress source ("media"|"volume"|"battery"), color, track, seek (click to seek)
//   image    src (file path or URL), radius, fit ("cover"|"contain")
//   shape    color, radius, opacity
//   clock    color, hand (second-hand colour), face (dial colour or "")   — an analog clock
//   app      name, command (what to run), icon (icon-theme name or image path), size, color
//   weather  city, color, unit ("C"|"F")      — current weather, today's high/low (MET Norway)
//   calendar color, accent                     — this month, today marked
//   note     text, size, color                 — a sticky note you type into on the desktop
//   (progress also takes source "cpu" | "ram" | "gpu", track colour, thick)
// every item: rotation (degrees), opacity (0..1), anim ("none" | "pulse" | "float" | "spin" | "glow")
// text extras: italic, underline, outline (colour), outlineWidth, spacing (letter spacing), font,
//   spans: { "w3": { color, bold }, "c0": {...} } — colour single words (w<i>) or letters (c<i>)
// widget: dynamic (colours from the playing album cover), dynamicTheme (also tints FreeForm's accent)
import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: wv
    property var widget: ({ w: 320, h: 120, items: [] })
    property var ctx: null
    property string fam: "Open Runde"
    property bool editing: false            // the editor: buttons don't run, items can be selected
    property int selected: -1
    signal picked(int index)
    signal itemEdited(int index, string key, var value)     // a sticky note typed into on the desktop

    width: widget.w || 320; height: widget.h || 120

    // Dynamic mode: the average colour of the playing album cover (read from a 1x1 drawing of it)
    property color artColor: "transparent"
    readonly property string artSrc: widget.dynamic && ctx && ctx.player ? ctx.player.trackArtUrl || "" : ""
    onArtSrcChanged: if (artSrc !== "") artProbe.loadImage(artSrc)
    Canvas {
        id: artProbe
        width: 1; height: 1; visible: false
        onImageLoaded: requestPaint()
        onPaint: {
            if (wv.artSrc === "" || !isImageLoaded(wv.artSrc)) return;
            var c = getContext("2d");
            c.drawImage(wv.artSrc, 0, 0, 1, 1);
            var px = c.getImageData(0, 0, 1, 1).data;
            wv.artColor = Qt.rgba(px[0] / 255, px[1] / 255, px[2] / 255, 1);
            // "Album colours for the whole theme": FreeForm's accent follows the cover too
            if (wv.widget.dynamicTheme && !wv.editing && wv.ctx && wv.ctx.hub && wv.ctx.hub.dock)
                wv.ctx.hub.dock.accent = Qt.lighter(wv.artColor, 1.3);
        }
    }
    // a widget fades and settles in when it appears on the desktop
    opacity: 0; scale: 0.96
    Component.onCompleted: { opacity = 1; scale = 1; }
    Behavior on opacity { NumberAnimation { duration: 260 } }
    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

    // a text with some words / letters coloured (spans), as Qt's StyledText
    function styled(text, d) {
        var sp = d.spans || {}, keys = Object.keys(sp);
        if (keys.length === 0) return null;
        var esc = function (t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); };
        var wrap = function (t, st) {
            if (!st) return esc(t);
            var o = esc(t);
            if (st.bold) o = "<b>" + o + "</b>";
            if (st.italic) o = "<i>" + o + "</i>";
            if (st.underline) o = "<u>" + o + "</u>";
            if (st.color) o = "<font color=\"" + st.color + "\">" + o + "</font>";
            return o;
        };
        if (keys[0].charAt(0) === "c") {
            var out = "";
            for (var i = 0; i < text.length; i++) out += wrap(text.charAt(i), sp["c" + i]);
            return out;
        }
        var words = String(text).split(" "), res = [];
        for (var j = 0; j < words.length; j++) res.push(wrap(words[j], sp["w" + j]));
        return res.join(" ");
    }

    function url(p) {
        if (!p) return "";
        if (/^[a-z]+:/i.test(p) && !/^[a-z]:[\\/]/i.test(p)) return p;
        return "file:///" + String(p).split(String.fromCharCode(92)).join("/").replace(/^\/+/, "");
    }

    // background card
    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: wv.widget.bg ? (wv.widget.bg.radius !== undefined ? wv.widget.bg.radius : 22) : 22
        color: wv.widget.dynamic && wv.artColor.a > 0 ? Qt.darker(wv.artColor, 1.6)
             : (wv.widget.bg && wv.widget.bg.color ? wv.widget.bg.color : "#1C1C1E")
        Behavior on color { ColorAnimation { duration: 600 } }
        opacity: wv.widget.bg && wv.widget.bg.opacity !== undefined ? wv.widget.bg.opacity : 0.85
        border.width: wv.widget.bg && wv.widget.bg.border ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.16)
    }
    Item {
        id: clipArea
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: clipMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }

        Repeater {
            model: wv.widget.items || []
            delegate: Item {
                id: it
                required property var modelData
                required property int index
                readonly property var d: modelData
                x: d.x || 0; y: d.y || 0
                width: d.w || 40; height: d.h || 20
                rotation: (d.rotation || 0) + anim.spinAngle
                opacity: (d.opacity !== undefined ? d.opacity : 1) * anim.glowLevel
                transformOrigin: Item.Center
                transform: Translate { y: anim.floatY }
                scale: anim.pulseScale
                // per-item animation
                QtObject {
                    id: anim
                    property real pulseScale: 1
                    property real floatY: 0
                    property real spinAngle: 0
                    property real glowLevel: 1
                }
                SequentialAnimation {
                    running: it.d.anim === "pulse"; loops: Animation.Infinite
                    onRunningChanged: if (!running) anim.pulseScale = 1
                    NumberAnimation { target: anim; property: "pulseScale"; to: 1.06; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { target: anim; property: "pulseScale"; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
                SequentialAnimation {
                    running: it.d.anim === "float"; loops: Animation.Infinite
                    onRunningChanged: if (!running) anim.floatY = 0
                    NumberAnimation { target: anim; property: "floatY"; to: -4; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { target: anim; property: "floatY"; to: 0; duration: 1400; easing.type: Easing.InOutSine }
                }
                NumberAnimation {
                    running: it.d.anim === "spin"; loops: Animation.Infinite
                    target: anim; property: "spinAngle"; from: 0; to: 360; duration: 6000
                    onRunningChanged: if (!running) anim.spinAngle = 0
                }
                SequentialAnimation {
                    running: it.d.anim === "glow"; loops: Animation.Infinite
                    onRunningChanged: if (!running) anim.glowLevel = 1
                    NumberAnimation { target: anim; property: "glowLevel"; to: 0.55; duration: 1000; easing.type: Easing.InOutSine }
                    NumberAnimation { target: anim; property: "glowLevel"; to: 1; duration: 1000; easing.type: Easing.InOutSine }
                }

                // ── text ──
                Text {
                    visible: it.d.type === "text"
                    anchors.fill: parent
                    readonly property string plain: wv.ctx ? wv.ctx.fill(it.d.text) : (it.d.text || "")
                    readonly property var rich: it.d.type === "text" ? wv.styled(plain, it.d) : null
                    text: rich !== null ? rich : plain
                    textFormat: rich !== null ? Text.StyledText : Text.PlainText
                    color: it.d.color || "white"
                    font.family: it.d.font || wv.fam; font.pixelSize: it.d.size || 14
                    font.weight: it.d.bold ? Font.Bold : Font.Normal
                    font.italic: !!it.d.italic; font.underline: !!it.d.underline
                    font.letterSpacing: it.d.spacing || 0
                    style: it.d.outline ? Text.Outline : Text.Normal
                    styleColor: it.d.outline || "black"
                    horizontalAlignment: it.d.align === "center" ? Text.AlignHCenter : it.d.align === "right" ? Text.AlignRight : Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                // ── album art ──
                Item {
                    visible: it.d.type === "art"
                    anchors.fill: parent
                    Rectangle { id: artMask; anchors.fill: parent; radius: it.d.radius !== undefined ? it.d.radius : 10; visible: false; layer.enabled: true }
                    Rectangle {
                        anchors.fill: parent; radius: artMask.radius
                        gradient: Gradient { GradientStop { position: 0; color: "#FF375F" } GradientStop { position: 1; color: "#AF52DE" } }
                        WGlyph { anchors.centerIn: parent; width: parent.width * 0.4; height: width; kind: "note"; color: "white" }
                    }
                    Image {
                        anchors.fill: parent
                        source: wv.ctx && wv.ctx.player ? wv.ctx.player.trackArtUrl || "" : ""
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: artMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                }
                // ── image ──
                Item {
                    visible: it.d.type === "image"
                    anchors.fill: parent
                    Rectangle { id: imgMask; anchors.fill: parent; radius: it.d.radius || 0; visible: false; layer.enabled: true }
                    Rectangle { anchors.fill: parent; radius: imgMask.radius; color: Qt.rgba(1, 1, 1, 0.08); visible: img.status !== Image.Ready }
                    Image {
                        id: img
                        anchors.fill: parent
                        source: it.d.type === "image" ? wv.url(it.d.src) : ""
                        fillMode: it.d.fit === "contain" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                        asynchronous: true; smooth: true
                        layer.enabled: (it.d.radius || 0) > 0
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: imgMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                }
                // ── analog clock ──
                Item {
                    visible: it.d.type === "clock"
                    anchors.fill: parent
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height); height: width; radius: width / 2
                        color: it.d.face !== undefined ? (it.d.face || "transparent") : "#FFFFFF"
                    }
                    Canvas {
                        id: clk
                        anchors.fill: parent
                        visible: it.d.type === "clock"
                        property var t: wv.ctx ? wv.ctx.now : new Date()
                        onTChanged: requestPaint()
                        onPaint: {
                            var c = getContext("2d"); c.reset();
                            var r = Math.min(width, height) / 2, cx = width / 2, cy = height / 2, col = it.d.color || "#1C1C1E";
                            c.strokeStyle = col; c.fillStyle = col; c.lineCap = "round";
                            for (var i = 0; i < 12; i++) {
                                var a = i * Math.PI / 6;
                                c.lineWidth = i % 3 === 0 ? r * 0.05 : r * 0.025;
                                c.beginPath(); c.moveTo(cx + Math.sin(a) * r * 0.78, cy - Math.cos(a) * r * 0.78);
                                c.lineTo(cx + Math.sin(a) * r * 0.9, cy - Math.cos(a) * r * 0.9); c.stroke();
                            }
                            function hand(a, len, w, color) { c.strokeStyle = color; c.lineWidth = w; c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + Math.sin(a) * len, cy - Math.cos(a) * len); c.stroke(); }
                            var h = t.getHours() % 12, m = t.getMinutes(), s = t.getSeconds();
                            hand((h + m / 60) * Math.PI / 6, r * 0.5, r * 0.08, col);
                            hand((m + s / 60) * Math.PI / 30, r * 0.72, r * 0.055, col);
                            hand(s * Math.PI / 30, r * 0.8, r * 0.02, it.d.hand || "#FF9F0A");
                            c.fillStyle = it.d.hand || "#FF9F0A"; c.beginPath(); c.arc(cx, cy, r * 0.05, 0, Math.PI * 2); c.fill();
                        }
                    }
                }
                // ── weather ──
                Item {
                    visible: it.d.type === "weather"
                    anchors.fill: parent
                    readonly property var wx: it.d.type === "weather" && wv.ctx ? wv.ctx.weatherFor(it.d.city) : ({})
                    readonly property bool far: it.d.unit === "F"
                    function deg(c) { return c === null || c === undefined ? "--" : Math.round(far ? c * 9 / 5 + 32 : c) + "\u00B0"; }
                    Column {
                        anchors.fill: parent; spacing: 2
                        Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.wx.place || it.d.city || "Weather"; color: it.d.color || "white"; font.family: wv.fam; font.pixelSize: Math.max(11, parent.height * 0.13); font.weight: Font.DemiBold }
                        Text { text: parent.parent.wx.state === "ok" ? parent.parent.deg(parent.parent.wx.temp) : "--"; color: it.d.color || "white"; font.family: wv.fam; font.pixelSize: Math.max(18, parent.height * 0.36); font.weight: Font.Light }
                        Text { text: wv.ctx ? wv.ctx.weatherGlyph(parent.parent.wx.symbol) : ""; color: it.d.color || "white"; font.pixelSize: Math.max(12, parent.height * 0.14) }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: parent.parent.wx.state === "ok" ? parent.parent.wx.text : parent.parent.wx.state === "loading" ? "Loading\u2026" : (parent.parent.wx.text || "")
                            color: it.d.color || "white"; font.family: wv.fam; font.pixelSize: Math.max(10, parent.height * 0.1); font.weight: Font.DemiBold
                        }
                        Text {
                            visible: parent.parent.wx.state === "ok" && parent.parent.wx.high !== null
                            text: "H:" + parent.parent.deg(parent.parent.wx.high) + "  L:" + parent.parent.deg(parent.parent.wx.low)
                            color: it.d.color || "white"; opacity: 0.85; font.family: wv.fam; font.pixelSize: Math.max(10, parent.height * 0.1)
                        }
                    }
                }
                // ── calendar (this month) ──
                Item {
                    visible: it.d.type === "calendar"
                    anchors.fill: parent
                    readonly property date t: wv.ctx ? wv.ctx.now : new Date()
                    readonly property int first: new Date(t.getFullYear(), t.getMonth(), 1).getDay()
                    readonly property int days: new Date(t.getFullYear(), t.getMonth() + 1, 0).getDate()
                    readonly property real cw: width / 7
                    readonly property real ch: (height - cw * 0.9) / 7
                    Text { width: parent.width; text: Qt.formatDate(parent.t, "MMMM").toUpperCase(); color: it.d.accent || "#FF453A"; font.family: wv.fam; font.pixelSize: Math.max(9, parent.cw * 0.42); font.weight: Font.Bold }
                    Grid {
                        y: parent.cw * 0.9; columns: 7
                        Repeater {
                            model: 7 + 42
                            delegate: Item {
                                required property int index
                                readonly property int day: index - 7 - parent.parent.first + 1
                                readonly property bool head: index < 7
                                readonly property bool today: !head && day === parent.parent.t.getDate()
                                width: parent.parent.cw; height: parent.parent.ch
                                visible: head || (day >= 1 && day <= parent.parent.days)
                                Rectangle { anchors.centerIn: parent; width: Math.min(parent.width, parent.height) * 0.9; height: width; radius: width / 2; color: it.d.accent || "#FF453A"; visible: parent.today }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.head ? "SMTWTFS".charAt(parent.index) : parent.day
                                    color: parent.today ? "white" : (it.d.color || "white"); opacity: parent.head ? 0.6 : 1
                                    font.family: wv.fam; font.pixelSize: Math.max(8, Math.min(parent.width, parent.height) * 0.5); font.weight: parent.today || parent.head ? Font.Bold : Font.Normal
                                }
                            }
                        }
                    }
                }
                // ── sticky note ──
                Flickable {
                    visible: it.d.type === "note"
                    anchors.fill: parent
                    contentHeight: noteEdit.paintedHeight; clip: true
                    interactive: !wv.editing
                    TextEdit {
                        id: noteEdit
                        width: parent.width
                        enabled: !wv.editing                 // in the editor the block is moved, not typed into
                        text: it.d.text || ""
                        wrapMode: TextEdit.Wrap
                        color: it.d.color || "#1C1C1E"
                        selectByMouse: true
                        font.family: wv.fam; font.pixelSize: it.d.size || 15
                        onEditingFinished: if (text !== (it.d.text || "")) wv.itemEdited(it.index, "text", text)
                        Text { visible: noteEdit.text === "" && !noteEdit.activeFocus; text: "Type a note\u2026"; color: noteEdit.color; opacity: 0.45; font: noteEdit.font }
                    }
                }
                // ── app shortcut ──
                Item {
                    id: appIt
                    visible: it.d.type === "app"
                    anchors.fill: parent
                    readonly property string iconSrc: !it.d.icon ? "" : (/[\\/.]/.test(it.d.icon) ? wv.url(it.d.icon) : Quickshell.iconPath(it.d.icon, true))
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        scale: ama.pressed && !wv.editing ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(appIt.width, appIt.height - (it.d.name ? 20 : 0)); height: width
                            Image { anchors.fill: parent; source: appIt.iconSrc; visible: status === Image.Ready; sourceSize: Qt.size(width * 2, height * 2); smooth: true; mipmap: true }
                            Rectangle {
                                anchors.fill: parent; radius: width * 0.225; visible: appIt.iconSrc === ""
                                gradient: Gradient { GradientStop { position: 0; color: "#5E5CE6" } GradientStop { position: 1; color: "#0A84FF" } }
                                Text { anchors.centerIn: parent; text: (it.d.name || "?").charAt(0).toUpperCase(); color: "white"; font.pixelSize: parent.width * 0.45; font.weight: Font.Bold }
                            }
                        }
                        Text {
                            visible: !!it.d.name
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: appIt.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: it.d.name || ""; color: it.d.color || "white"
                            font.family: wv.fam; font.pixelSize: it.d.size || 12
                        }
                    }
                    MouseArea {
                        id: ama
                        anchors.fill: parent
                        enabled: !wv.editing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (wv.ctx) wv.ctx.run("open.app", it.d.command || "")
                    }
                }
                // ── shape ──
                Rectangle {
                    visible: it.d.type === "shape"
                    anchors.fill: parent
                    radius: it.d.radius || 0
                    color: it.d.color || "#0A84FF"
                    opacity: it.d.opacity !== undefined ? it.d.opacity : 1
                }
                // ── progress ──
                Item {
                    visible: it.d.type === "progress"
                    anchors.fill: parent
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: Math.min(parent.height, it.d.thick || 6); radius: height / 2
                        color: it.d.track || Qt.rgba(1, 1, 1, 0.22)
                        Rectangle {
                            width: parent.width * (wv.ctx ? wv.ctx.progressOf(it.d.source || "media") : 0.4)
                            height: parent.height; radius: parent.radius
                            color: it.d.color || "white"
                            Behavior on width { NumberAnimation { duration: 400 } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !wv.editing && (it.d.source || "media") !== "battery"
                        onClicked: mouse => {
                            var f = mouse.x / width, c = wv.ctx;
                            if (!c) return;
                            if ((it.d.source || "media") === "volume") { if (c.sink && c.sink.audio) c.sink.audio.volume = f; }
                            else if (c.player && c.player.canSeek && c.player.length > 0) c.player.position = f * c.player.length;
                        }
                    }
                }
                // ── button ──
                Rectangle {
                    id: btn
                    visible: it.d.type === "button"
                    anchors.fill: parent
                    radius: Math.min(width, height) / 2
                    color: it.d.fill ? it.d.fill : (bma.containsMouse && !wv.editing ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                    scale: bma.pressed && !wv.editing ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        WGlyph {
                            visible: it.d.icon !== "none"
                            width: Math.min(btn.width, btn.height) * (it.d.label ? 0.42 : 0.55); height: width
                            anchors.verticalCenter: parent.verticalCenter
                            kind: wv.ctx ? wv.ctx.iconFor(it.d) : (it.d.icon || "play")
                            color: it.d.color || "white"
                        }
                        Text {
                            visible: !!it.d.label
                            anchors.verticalCenter: parent.verticalCenter
                            text: it.d.label || ""
                            color: it.d.color || "white"
                            font.family: wv.fam; font.pixelSize: it.d.size || 13; font.weight: Font.DemiBold
                        }
                    }
                    MouseArea {
                        id: bma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !wv.editing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (wv.ctx) wv.ctx.run(it.d.action || "none", it.d.param || "")
                    }
                }
                // editor: click to select
                MouseArea {
                    anchors.fill: parent
                    enabled: wv.editing
                    onPressed: wv.picked(it.index)
                }
                Rectangle {
                    visible: wv.editing && wv.selected === it.index
                    anchors.fill: parent; anchors.margins: -2
                    color: "transparent"; radius: 4
                    border.width: 2; border.color: "#0A84FF"
                }
            }
        }
    }
    Rectangle { id: clipMask; anchors.fill: parent; radius: bgRect.radius; visible: false; layer.enabled: true }
}
