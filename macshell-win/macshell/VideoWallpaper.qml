// Animated / video wallpaper on Windows (Linux uses mpvpaper through macshell-setwall.sh).
// One looping, muted video per screen, below every window; pauses while a fullscreen app runs.
// Loaded by shell.qml only on Windows, only while Settings > Wallpaper has a video selected.
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

Variants {
    id: vw
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    readonly property string file: bar ? bar.wallpaperVideo : ""
    readonly property bool paused: !!(ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.fullscreen)
    model: Quickshell.screens

    PanelWindow {
        required property var modelData
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "freeform-wallpaper"
        Video {
            anchors.fill: parent
            source: vw.file ? "file:///" + vw.file.split(String.fromCharCode(92)).join("/").replace(/^\/+/, "") : ""
            fillMode: VideoOutput.PreserveAspectCrop
            loops: MediaPlayer.Infinite
            muted: true
            autoPlay: true
            onSourceChanged: play()
            Connections {
                target: vw
                function onPausedChanged() { if (vw.paused) parent.pause(); else parent.play(); }
            }
        }
    }
}
