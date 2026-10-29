// Windows-style caption buttons for FreeForm's own app windows: minimize, maximize / restore, close,
// in the top-right corner like every Windows app (46 x 32 each; close turns red on hover).
//   WinCaption { window: win; dark: true; anchors.top: parent.top; anchors.right: parent.right }
import QtQuick

Row {
    id: cap
    property var window: null
    property bool dark: true
    property bool canMaximize: true
    readonly property color fg: dark ? "#FFFFFF" : "#1A1A1A"
    readonly property bool maxed: window ? window.visibility === Window.Maximized : false

    Repeater {
        model: cap.canMaximize ? ["min", "max", "close"] : ["min", "close"]
        delegate: Rectangle {
            id: b
            required property string modelData
            width: 46; height: 32
            color: ma.containsMouse ? (b.modelData === "close" ? (ma.pressed ? "#94141C" : "#C42B1C")
                                                                : (cap.dark ? Qt.rgba(1, 1, 1, ma.pressed ? 0.06 : 0.09) : Qt.rgba(0, 0, 0, ma.pressed ? 0.06 : 0.09)))
                                    : "transparent"
            readonly property color ink: b.modelData === "close" && ma.containsMouse ? "white" : cap.fg
            // minimize: a short line
            Rectangle { visible: b.modelData === "min"; anchors.centerIn: parent; width: 10; height: 1; color: b.ink }
            // maximize: a square; restore: two overlapping squares
            Rectangle {
                visible: b.modelData === "max"; anchors.centerIn: parent
                anchors.horizontalCenterOffset: cap.maxed ? -1 : 0; anchors.verticalCenterOffset: cap.maxed ? 1 : 0
                width: cap.maxed ? 8 : 10; height: width; radius: 1.5; color: "transparent"; border.width: 1; border.color: b.ink
            }
            Rectangle {
                visible: b.modelData === "max" && cap.maxed; anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1; anchors.verticalCenterOffset: -1
                width: 8; height: 8; radius: 1.5; color: "transparent"; border.width: 1; border.color: b.ink
                z: -1
            }
            // close: an X
            Item {
                visible: b.modelData === "close"; anchors.centerIn: parent; width: 10; height: 10
                Rectangle { anchors.centerIn: parent; width: 13.5; height: 1; rotation: 45; color: b.ink; antialiasing: true }
                Rectangle { anchors.centerIn: parent; width: 13.5; height: 1; rotation: -45; color: b.ink; antialiasing: true }
            }
            MouseArea {
                id: ma
                anchors.fill: parent; hoverEnabled: true
                onClicked: {
                    if (!cap.window) return;
                    if (b.modelData === "min") cap.window.showMinimized();
                    else if (b.modelData === "max") { if (cap.maxed) cap.window.showNormal(); else cap.window.showMaximized(); }
                    else cap.window.visible = false;
                }
            }
        }
    }
}
