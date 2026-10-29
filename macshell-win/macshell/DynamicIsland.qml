// Dynamic Island (Windows): a black pill at the top centre, just under the menu bar (so the bar
// stays visible and clickable), that only exists while it has something to say. It drops in as a
// small pill (5 px under the bar, 30 px tall), then widens to fit what it shows:
//   Caps Lock on   [caps glyph]  Caps Lock  [caps glyph]   (stays while Caps Lock is on)
//   a notification [app icon]  App · Sender / message      (5 s, then it tucks away)
// Loaded by shell.qml on Windows; MacBar hands it notifications (hub.island.notify).
// Notification sounds: Settings > Notifications picks a sound for every app ("*") or per app;
// kept in ~/.config/macshell/notification-sounds.json as { "*": "C:/...wav", "Discord": "..." }.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland        // PanelWindow layers + our Windows types (WinCapsLock)

PanelWindow {
    id: island
    property var hub: null
    readonly property string fam: hub && hub.dock ? hub.dock.fontFamily : "Open Runde"

    // what it shows: "" (nothing), "caps" or "notif"
    property var note: null                         // { app, summary, body, icon }
    // a desktop widget in Move mode (right-click > Move): the island becomes its toolbar
    readonly property var studio: hub ? hub.widgetStudio : null
    readonly property int editing: studio ? studio.movingIndex : -1
    readonly property string mode: editing >= 0 ? "edit" : (note ? "notif" : (caps.on ? "caps" : ""))
    function notify(rec) {
        note = rec; noteTimer.restart();
        var snd = soundFor(rec.app);
        if (snd !== "" && hub && hub.bar && hub.bar.uiSounds) Quickshell.execDetached(["pw-play", "--volume=0.9", snd]);
    }
    readonly property real barH: hub && hub.bar ? hub.bar.barHeight : 28

    // ── custom notification sounds ──
    property var sounds: ({})
    function soundFor(app) { return sounds[app] || sounds["*"] || ""; }
    function setSound(app, path) {
        var m = JSON.parse(JSON.stringify(sounds));
        if (path) m[app] = path; else delete m[app];
        sounds = m; soundsFile.setText(JSON.stringify(m, null, 1));
    }
    function testSound(app) { var s = soundFor(app); if (s) Quickshell.execDetached(["pw-play", "--volume=0.9", s]); }
    FileView {
        id: soundsFile
        path: (Quickshell.env("HOME") || Quickshell.env("USERPROFILE")) + "/.config/macshell/notification-sounds.json"
        printErrors: false
        onLoaded: { try { island.sounds = JSON.parse(text()) || {}; } catch (e) {} }
    }

    WinCapsLock { id: caps }
    Timer { id: noteTimer; interval: 5200; onTriggered: island.note = null }

    anchors { top: true; left: true; right: true }
    implicitHeight: 150
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "freeform-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: pill.y > -pill.height + 1 || island.mode !== ""
    mask: Region { item: pill }

    readonly property real targetW: mode === "edit" ? editRow.implicitWidth + 24 : mode === "notif" ? 380 : mode === "caps" ? 168 : 30
    readonly property real targetH: mode === "edit" ? 40 : mode === "notif" ? 70 : 30

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        // step 1: drop in as a small pill; step 2 (after it lands): widen to the content
        property bool landed: false
        y: island.mode !== "" ? island.barH + 5 : -height - 4
        width: landed ? island.targetW : 30
        height: landed ? island.targetH : 30
        radius: Math.min(height / 2, 22)
        color: "#000000"
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08)
        clip: true
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Timer { id: landTimer; interval: 230; onTriggered: pill.landed = true }
        Connections {
            target: island
            function onModeChanged() { if (island.mode === "") pill.landed = false; else if (!pill.landed) landTimer.restart(); }
        }

        // the Caps Lock glyph: an upward arrow over a bar (drawn; same on both sides)
        component CapsGlyph: Canvas {
            width: 14; height: 16
            onPaint: {
                var c = getContext("2d"); c.reset();
                c.strokeStyle = "white"; c.lineWidth = 1.6; c.lineJoin = "round";
                c.beginPath();
                c.moveTo(7, 1.5); c.lineTo(13, 8); c.lineTo(9.5, 8); c.lineTo(9.5, 11); c.lineTo(4.5, 11); c.lineTo(4.5, 8); c.lineTo(1, 8); c.closePath();
                c.stroke();
                c.fillStyle = "white"; c.fillRect(4.5, 13, 5, 1.8);
            }
        }

        // Caps Lock
        Row {
            anchors.centerIn: parent; spacing: 10
            opacity: island.mode === "caps" && pill.landed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            CapsGlyph { anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Caps Lock"; color: "white"; font.family: island.fam; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            CapsGlyph { anchors.verticalCenter: parent.verticalCenter }
        }

        // widget toolbar: size, turn, move by one square, Done
        Row {
            id: editRow
            anchors.centerIn: parent; spacing: 4
            opacity: island.mode === "edit" && pill.landed ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            component IBtn: Rectangle {
                id: ib
                property string label: ""
                property bool on: false
                signal clicked()
                width: Math.max(28, ibT.implicitWidth + 16); height: 28; radius: 14
                color: on ? "#0A84FF" : (ibM.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                Text { id: ibT; anchors.centerIn: parent; text: ib.label; color: "white"; font.family: island.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                MouseArea { id: ibM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
            }
            readonly property var w: island.studio && island.editing >= 0 ? island.studio.widgets[island.editing] : null
            readonly property int cols: w ? island.studio.cellsOf(w.w) : 0
            readonly property int rows: w ? island.studio.cellsOf(w.h) : 0
            Repeater {
                model: [[1, 1], [2, 1], [1, 2], [2, 2], [4, 2]]
                delegate: IBtn {
                    required property var modelData
                    label: modelData[0] + "\u00D7" + modelData[1]
                    on: editRow.cols === modelData[0] && editRow.rows === modelData[1]
                    onClicked: island.studio.sizeDesktop(island.editing, modelData[0], modelData[1])
                }
            }
            Item { width: 6; height: 1 }
            IBtn { label: "\u21BB"; onClicked: island.studio.rotateDesktop(island.editing) }      // turn a quarter
            Item { width: 6; height: 1 }
            IBtn { label: "\u2190"; onClicked: island.studio.nudgeDesktop(island.editing, -1, 0) }
            IBtn { label: "\u2191"; onClicked: island.studio.nudgeDesktop(island.editing, 0, -1) }
            IBtn { label: "\u2193"; onClicked: island.studio.nudgeDesktop(island.editing, 0, 1) }
            IBtn { label: "\u2192"; onClicked: island.studio.nudgeDesktop(island.editing, 1, 0) }
            Item { width: 6; height: 1 }
            IBtn { label: "Done"; on: true; onClicked: island.studio.movingIndex = -1 }
        }

        // a notification: who it's from and which app
        Item {
            anchors.fill: parent
            opacity: island.mode === "notif" && pill.landed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Rectangle {
                id: noteIcon
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 42; height: 42; radius: 11; color: "#1C1C1E"; clip: true
                Image {
                    anchors.fill: parent; source: island.note && island.note.icon ? island.note.icon : ""
                    fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true; mipmap: true
                }
                Text {
                    visible: !(island.note && island.note.icon)
                    anchors.centerIn: parent; color: "white"; font.family: island.fam; font.pixelSize: 18; font.weight: Font.Bold
                    text: island.note && island.note.app ? island.note.app.charAt(0).toUpperCase() : "!"
                }
            }
            Column {
                x: noteIcon.x + noteIcon.width + 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 20; spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: island.note ? (island.note.app || "") : ""
                    color: Qt.rgba(1, 1, 1, 0.55); font.family: island.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: island.note ? (island.note.summary || "") : ""
                    color: "white"; font.family: island.fam; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: island.note ? String(island.note.body || "").replace(/<[^>]*>/g, "") : ""
                    color: Qt.rgba(1, 1, 1, 0.8); font.family: island.fam; font.pixelSize: 12
                }
            }
            MouseArea { anchors.fill: parent; onClicked: island.note = null }     // click to dismiss
        }
    }
}
