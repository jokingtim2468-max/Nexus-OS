// FreeForm's desktop on Windows: one window per screen at the very bottom that covers Explorer's
// desktop (icons included) with FreeForm's wallpaper — the picture from Settings > Wallpaper, or a
// looping muted video (pauses behind fullscreen apps) — and a Mac-style right-click menu.
// Wallpaper Engine draws its own layer; while one plays, this layer stays out of the way.
// Loaded by shell.qml only on Windows (Linux has the compositor's own background).
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import "I18n.js" as I18n

Variants {
    id: dl
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    readonly property var dock: hub ? hub.dock : null
    readonly property string picture: bar ? bar.wallpaperPath : ""
    readonly property string video: bar ? bar.wallpaperVideo : ""
    readonly property bool engine: bar ? bar.weCurrent !== "" : false
    readonly property bool paused: !!(ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.fullscreen)
    readonly property bool dark: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    function url(p) { return p ? "file:///" + String(p).split(String.fromCharCode(92)).join("/").replace(/^\/+/, "") : ""; }
    model: Quickshell.screens
    // Windows has no compositor wallpaper to read: start on FreeForm's own, so the glass has something to refract
    onBarChanged: {
        if (Qt.platform.os !== "windows" || !bar || bar.wallpaperPath !== "") return;
        var p = decodeURIComponent(String(Qt.resolvedUrl("assets/wallpapers/FreeForm Tide-" + (dark ? "Dark" : "Light") + ".jpg"))).replace(/^file:\/\/\//, "");
        bar.wallpaperPath = p;
        if (dock) dock.wallpaperPath = p;
    }

    PanelWindow {
        id: desk
        required property var modelData
        screen: modelData
        visible: !dl.engine
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "freeform-desktop"

        Image {
            anchors.fill: parent
            visible: dl.video === ""
            // nothing picked yet: FreeForm's own wallpaper
            source: dl.picture !== "" ? dl.url(dl.picture)
                    : Qt.resolvedUrl("assets/wallpapers/FreeForm Tide-" + (dl.dark ? "Dark" : "Light") + ".jpg")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true; smooth: true; cache: false
            sourceSize: Qt.size(desk.width, desk.height)
        }
        Loader {
            anchors.fill: parent
            active: dl.video !== ""
            sourceComponent: Video {
                source: dl.url(dl.video)
                fillMode: VideoOutput.PreserveAspectCrop
                loops: MediaPlayer.Infinite
                muted: true
                autoPlay: true
                Connections {
                    target: dl
                    function onPausedChanged() { if (dl.paused) parent.pause(); else parent.play(); }
                }
            }
        }

        // ── right-click menu, macOS desktop style ──
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) { menu.x = Math.min(mouse.x, desk.width - menu.width - 8); menu.y = Math.min(mouse.y, desk.height - menu.height - 8); menu.visible = true; }
                else menu.visible = false;
            }
        }
        Rectangle {
            id: menu
            visible: false
            width: 230; height: col.implicitHeight + 10
            radius: 10
            color: dl.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.97)
            border.width: 1; border.color: dl.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.7; shadowOpacity: 0.35; shadowVerticalOffset: 5 }
            Column {
                id: col
                x: 5; y: 5; width: parent.width - 10
                Repeater {
                    model: [
                        { t: "Change Wallpaper…", a: "wallpaper" },
                        { t: "Edit Widgets…", a: "widgets" },
                        { t: "Themes…", a: "appearance" },
                        { sep: true },
                        { t: "App Store…", a: "appstore" },
                        { t: "System Settings…", a: "settings" }
                    ]
                    delegate: Item {
                        id: mi
                        required property var modelData
                        width: col.width; height: modelData.sep ? 9 : 26
                        Rectangle { visible: !!mi.modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: dl.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1) }
                        Rectangle {
                            visible: !mi.modelData.sep
                            anchors.fill: parent; radius: 5
                            color: mma.containsMouse ? (dl.dock ? dl.dock.accent : "#0A84FF") : "transparent"
                            Text {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr(mi.modelData.t || "")
                                color: mma.containsMouse ? "white" : (dl.dark ? "#F5F5F7" : "#1D1D1F")
                                font.family: dl.fam; font.pixelSize: 13
                            }
                            MouseArea {
                                id: mma
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    menu.visible = false;
                                    var h = dl.hub, a = mi.modelData.a;
                                    if (!h) return;
                                    if (a === "widgets" && h.widgetStudio) h.widgetStudio.open();
                                    else if (a === "appstore" && h.appStore) h.appStore.open("");
                                    else if (a === "settings") h.openSettings("general");
                                    else h.openSettings(a);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
