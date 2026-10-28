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

    width: widget.w || 320; height: widget.h || 120

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
        color: wv.widget.bg && wv.widget.bg.color ? wv.widget.bg.color : "#1C1C1E"
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

                // ── text ──
                Text {
                    visible: it.d.type === "text"
                    anchors.fill: parent
                    text: wv.ctx ? wv.ctx.fill(it.d.text) : (it.d.text || "")
                    color: it.d.color || "white"
                    font.family: wv.fam; font.pixelSize: it.d.size || 14
                    font.weight: it.d.bold ? Font.Bold : Font.Normal
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
                        width: parent.width; height: Math.min(parent.height, 6); radius: height / 2
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
