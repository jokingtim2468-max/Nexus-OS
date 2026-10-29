// Dynamic Island (Windows): a black pill at the top centre that only exists while it has
// something to say. It drops from the top edge as a small pill (5 px down, 30 px tall), then
// widens to fit what it shows:
//   Caps Lock on   [caps glyph]  Caps Lock  [caps glyph]   (stays while Caps Lock is on)
//   a notification [app icon]  App · Sender / message      (5 s, then it tucks away)
// Loaded by shell.qml on Windows; MacBar hands it notifications (hub.island.notify).
import QtQuick
import Quickshell
import Quickshell.Wayland        // PanelWindow layers + our Windows types (WinCapsLock)

PanelWindow {
    id: island
    property var hub: null
    readonly property string fam: hub && hub.dock ? hub.dock.fontFamily : "Open Runde"

    // what it shows: "" (nothing), "caps" or "notif"
    property var note: null                         // { app, summary, body, icon }
    readonly property string mode: note ? "notif" : (caps.on ? "caps" : "")
    function notify(rec) { note = rec; noteTimer.restart(); }

    WinCapsLock { id: caps }
    Timer { id: noteTimer; interval: 5200; onTriggered: island.note = null }

    anchors { top: true; left: true; right: true }
    implicitHeight: 110
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "freeform-island"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: pill.y > -pill.height + 1 || island.mode !== ""
    mask: Region { item: pill }

    readonly property real targetW: mode === "notif" ? 380 : mode === "caps" ? 168 : 30
    readonly property real targetH: mode === "notif" ? 70 : 30

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        // step 1: drop in as a small pill; step 2 (after it lands): widen to the content
        property bool landed: false
        y: island.mode !== "" ? 5 : -height - 4
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
