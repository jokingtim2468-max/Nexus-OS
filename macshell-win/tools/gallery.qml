import QtQuick
import "../macshell" as MS

// MacShell's own, unmodified components running on plain Qt (no Quickshell, no Hyprland).
Item {
    id: root
    width: 1440; height: 900
    readonly property string ms: Qt.resolvedUrl("../macshell/")
    readonly property url glassShader: ms + "liquidglass.frag.qsb"

    FontLoader { id: reg;  source: root.ms + "assets/fonts/OpenRunde-Regular.otf" }
    FontLoader { id: bold; source: root.ms + "assets/fonts/OpenRunde-Semibold.otf" }

    // wallpaper (busy enough that refraction is visible)
    Item {
        id: wall
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#7cc4ff" }
                GradientStop { position: 0.5; color: "#2f6fd6" }
                GradientStop { position: 1.0; color: "#123a8a" }
            }
        }
        Repeater {
            model: 9
            Rectangle {
                width: 260 + index * 30; height: width; radius: width / 2
                x: (index * 197) % 1300 - 80; y: (index * 131) % 760 - 60
                color: ["#ffffff", "#9fe0ff", "#5aa0ff", "#c8b6ff", "#ffd6a5"][index % 5]
                opacity: 0.35
            }
        }
    }
    ShaderEffectSource { id: wallSes; sourceItem: wall; live: true; mipmap: true; visible: false }

    Text {
        x: 40; y: 30; color: "white"; font.family: bold.name; font.pixelSize: 26
        text: "MacShell components — running on plain Qt (no Hyprland)"
    }

    // ── the real Liquid Glass slab (liquidglass.frag.qsb) refracting the wallpaper ──
    MS.GlassSlab {
        id: slab
        x: 40; y: 90; width: 420; height: 150; cornerR: 34
        src: wallSes; srcSize: Qt.size(root.width, root.height); origin: Qt.point(x, y)
        shaderUrl: root.glassShader
        Text { anchors.centerIn: parent; text: "Liquid Glass"; color: "white"; font.family: bold.name; font.pixelSize: 30 }
    }

    // ── controls ──
    Column {
        x: 500; y: 100; spacing: 22
        Row {
            spacing: 18
            MS.GlassSwitch { checked: true }
            MS.GlassSwitch { checked: false }
        }
        MS.GlassSlider { width: 300 }
        MS.GlassSegmented { width: 300 }
    }

    // ── widgets ──
    MS.ClockWidget    { x: 40;  y: 300; style: "dark";   size: "small"; fam: reg.name; boldFam: bold.name }
    MS.CalendarWidget { x: 260; y: 300; style: "liquid"; size: "medium"; fam: reg.name }
    MS.WeatherWidget  { x: 700; y: 300; style: "liquid"; size: "medium"; fam: reg.name; city: "Seattle" }
    MS.PlayerWidget   { x: 40;  y: 560 }
}
