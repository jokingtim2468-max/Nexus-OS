// Mission Control (FreeForm): every open window side by side, live, on a dimmed blurred-glass backdrop.
// Win+Tab on Windows (WindowsHotkeys.qml), `qs ipc call missioncontrol toggle` anywhere.
// Click a window to switch to it; Esc or a click on empty space closes.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: mc
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool dark: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    property bool open: false

    function toggle() { open = !open; }
    function close() { open = false; }
    function iconFor(t) {
        var e = null;
        try { e = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(t.appId) : DesktopEntries.byId(t.appId); } catch (err) {}
        return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            visible: mc.open || fade.running
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "freeform-missioncontrol"
            WlrLayershell.keyboardFocus: mc.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // the windows on this screen (all of them when the screen is unknown)
            readonly property var wins: {
                var out = [], vals = ToplevelManager.toplevels.values;
                for (var i = 0; i < vals.length; i++) {
                    var t = vals[i], ss = t.screens || [];
                    var here = ss.length === 0;
                    for (var j = 0; j < ss.length; j++) if (ss[j] && ss[j].name === w.modelData.name) here = true;
                    if (here) out.push(t);
                }
                return out;
            }

            Item {
                id: stage
                anchors.fill: parent
                focus: true
                opacity: mc.open ? 1 : 0
                Behavior on opacity { NumberAnimation { id: fade; duration: 220; easing.type: Easing.OutCubic } }
                Keys.onEscapePressed: mc.close()

                Rectangle { anchors.fill: parent; color: mc.dark ? "#C0101012" : "#A0E5E5EA" }
                MouseArea { anchors.fill: parent; onClicked: mc.close() }

                Text {
                    anchors.centerIn: parent
                    visible: w.wins.length === 0
                    text: "No open windows"
                    color: mc.dark ? "#C8C8CC" : "#3A3A3C"
                    font.family: mc.fam; font.pixelSize: 22
                }

                // a grid sized to fit every window on screen
                readonly property int n: w.wins.length
                readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n * (width / Math.max(1, height)) / 1.6)))
                readonly property int rows: Math.max(1, Math.ceil(n / cols))
                readonly property real cellW: (width - 120) / cols
                readonly property real cellH: (height - 160) / rows

                Flow {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 120, stage.cols * stage.cellW)
                    spacing: 0
                    Repeater {
                        model: w.wins
                        delegate: Item {
                            id: cell
                            required property var modelData
                            width: stage.cellW; height: stage.cellH
                            scale: mc.open ? 1 : 0.92
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                            Rectangle {
                                id: tile
                                readonly property real ar: shot.hasContent && shot.sourceSize.height > 0 ? shot.sourceSize.width / shot.sourceSize.height : 16 / 10
                                width: Math.min(cell.width - 36, (cell.height - 64) * ar)
                                height: width / ar
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (cell.height - 40 - height) / 2
                                radius: 12
                                color: mc.dark ? "#2C2C2E" : "#FFFFFF"
                                border.width: hover.hovered ? 3 : 1
                                border.color: hover.hovered ? (mc.dock ? mc.dock.accent : "#0A84FF") : (mc.dark ? "#40FFFFFF" : "#30000000")
                                clip: true

                                ScreencopyView {
                                    id: shot
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    captureSource: mc.open ? cell.modelData : null
                                    live: mc.open
                                }
                                // minimized or not capturable: the app's icon
                                Image {
                                    anchors.centerIn: parent
                                    visible: !shot.hasContent
                                    width: Math.min(96, parent.height * 0.5); height: width
                                    source: mc.iconFor(cell.modelData)
                                    sourceSize: Qt.size(width * 2, height * 2)
                                }
                                HoverHandler { id: hover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { cell.modelData.activate(); mc.close(); }
                                }
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: tile.bottom; anchors.topMargin: 10
                                spacing: 8
                                Image {
                                    width: 20; height: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: mc.iconFor(cell.modelData)
                                    sourceSize: Qt.size(40, 40)
                                }
                                Text {
                                    width: Math.min(implicitWidth, cell.width - 70)
                                    elide: Text.ElideRight
                                    text: cell.modelData.title || cell.modelData.appId
                                    color: mc.dark ? "#F2F2F7" : "#1C1C1E"
                                    font.family: mc.fam; font.pixelSize: 14; font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
