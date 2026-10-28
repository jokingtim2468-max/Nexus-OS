// Tutorial — FreeForm's first-run tour of the desktop.
//
//   qs -c MacShell ipc call tour start | stop          (also: Apple menu > Welcome Tour…)
//
// Runs once automatically (a marker in ~/.config/macshell/tour.json). The screen dims, a highlight
// moves to the part of the desktop being explained, and "Show Me" opens the real thing: Spotlight,
// the App Store, the Wi-Fi / Bluetooth menu, Appearance (themes), Wallpaper (incl. Wallpaper Engine)
// and System Settings. ← / → / Return / Esc work too.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string home: Quickshell.env("HOME") || Quickshell.env("USERPROFILE")
    readonly property string markerPath: home + "/.config/macshell/tour.json"

    property bool running: false
    property bool paused: false          // "Show Me" opened something: the tour steps aside until Continue
    property int step: 0
    readonly property bool showing: running && !paused

    // where the highlight goes: "none" (centred card), "bar", "apple", "status", "dock"
    readonly property var steps: [
        { at: "none", title: "Welcome to FreeForm",
          body: "Your desktop now works like a Mac. This quick tour shows you the basics: finding and installing apps, Wi-Fi and Bluetooth, themes, wallpapers and settings. It takes about a minute." },
        { at: "bar", title: "The menu bar",
          body: "Along the top: the menus of the app you're using on the left, and Wi-Fi, Bluetooth, sound, Control Center and the clock on the right. Everything here is clickable." },
        { at: "status", title: "Finding apps",
          body: "Click the magnifying glass and start typing: Spotlight finds apps, files and settings, does maths and converts units. Press Return to open the top hit.",
          action: "spotlight", actionText: "Show Me" },
        { at: "dock", title: "The Dock",
          body: "Your favourite apps live in the Dock. Open apps have a dot under them. Right-click an app and choose Options > Keep in Dock to pin it; drag icons to reorder them." },
        { at: "apple", title: "Installing apps",
          body: "The App Store (Apple menu > App Store…) installs apps from the Microsoft Store and other trusted sources with one click, and keeps them up to date under Updates.",
          action: "appstore", actionText: "Open App Store" },
        { at: "status", title: "Wi-Fi and Bluetooth",
          body: "Click the Wi-Fi (or cable) icon to join a network and switch Wi-Fi and Bluetooth on or off. Click the Bluetooth row to see your remembered devices. New devices are paired in Settings > Bluetooth.",
          action: "network", actionText: "Show Me" },
        { at: "none", title: "Themes",
          body: "Choose Light or Dark (or Auto), an accent colour and how glassy everything looks in Settings > Appearance.",
          action: "appearance", actionText: "Open Appearance" },
        { at: "none", title: "Wallpapers and Wallpaper Engine",
          body: "Pick a picture or an animated wallpaper in Settings > Wallpaper. If you have Wallpaper Engine, your Steam Workshop wallpapers are listed there too. Click one and it plays behind everything.",
          action: "wallpaper", actionText: "Open Wallpaper" },
        { at: "apple", title: "Make it yours",
          body: "Everything can be changed in System Settings (Apple menu > System Settings…): the Dock, the menu bar, Control Center, widgets, sounds, the lock screen and more.",
          action: "settings", actionText: "Open Settings" },
        { at: "none", title: "You're all set",
          body: "You can take this tour again any time from the Apple menu > Welcome Tour…" }
    ]
    readonly property var cur: steps[Math.max(0, Math.min(step, steps.length - 1))]

    function start() { step = 0; paused = false; running = true; }
    function resume() { paused = false; }
    function stop() {
        running = false; paused = false;
        marker.setText(JSON.stringify({ done: true, at: new Date().toISOString() }));
    }
    function next() { if (step < steps.length - 1) step++; else stop(); }
    function back() { if (step > 0) step--; }
    function doAction(a) {
        if (!hub) return;
        paused = true;
        if (a === "spotlight" && bar) bar.search();
        else if (a === "appstore" && hub.appStore) hub.appStore.open("discover");
        else if (a === "network" && bar) bar.netRequest(1);
        else if (a === "appearance") hub.openSettings("appearance");
        else if (a === "wallpaper") hub.openSettings("wallpaper");
        else if (a === "settings") hub.openSettings("general");
    }

    // first run: no marker yet -> start once the bar and Dock have settled
    FileView {
        id: marker
        path: root.markerPath
        printErrors: false
        onLoadFailed: firstRun.start()
    }
    Timer { id: firstRun; interval: 4000; onTriggered: root.start() }

    PanelWindow {
        id: overlay
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: root.showing || fade.opacity > 0.01
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "freeform-tour"
        WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // the highlighted rectangle, in window coordinates
        readonly property real barH: root.bar ? root.bar.barHeight : 28
        readonly property rect target: {
            var w = width, h = height, at = root.cur.at;
            if (at === "bar") return Qt.rect(0, 0, w, barH);
            if (at === "apple") return Qt.rect(4, 0, 230, barH);
            if (at === "status") return Qt.rect(w - 420, 0, 416, barH);
            if (at === "dock") {
                var d = root.dock, dw = d ? d.totalW0 + 28 : 600, dh = d ? d.bgHeight + 8 : 76, m = d ? d.margin : 6;
                return Qt.rect((w - dw) / 2, h - m - dh + 2, dw, dh);
            }
            return Qt.rect(w / 2, h / 2, 0, 0);
        }
        readonly property bool hasTarget: root.cur.at !== "none"

        Item {
            id: fade
            anchors.fill: parent
            opacity: root.showing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) root.stop();
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.next();
                else if (e.key === Qt.Key_Left) root.back();
                e.accepted = true;
            }

            // dim everything except the highlight (four rectangles around a hole that slides between targets)
            Item {
                id: hole
                x: overlay.target.x - 6; y: overlay.target.y - 4
                width: overlay.target.width + 12; height: overlay.target.height + 8
                Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
                Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
                Behavior on width { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
                Behavior on height { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
            }
            readonly property color dim: Qt.rgba(0, 0, 0, 0.55)
            Rectangle { x: 0; y: 0; width: parent.width; height: Math.max(0, hole.y); color: fade.dim }
            Rectangle { x: 0; y: hole.y + hole.height; width: parent.width; height: Math.max(0, parent.height - hole.y - hole.height); color: fade.dim }
            Rectangle { x: 0; y: hole.y; width: Math.max(0, hole.x); height: hole.height; color: fade.dim }
            Rectangle { x: hole.x + hole.width; y: hole.y; width: Math.max(0, parent.width - hole.x - hole.width); height: hole.height; color: fade.dim }
            // a soft ring around the highlight
            Rectangle {
                x: hole.x - 2; y: hole.y - 2; width: hole.width + 4; height: hole.height + 4
                visible: overlay.hasTarget
                radius: 12; color: "transparent"
                border.width: 2; border.color: root.accent
                SequentialAnimation on opacity {
                    running: root.showing && overlay.hasTarget; loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            // clicks outside the card don't fall through to the desktop
            MouseArea { anchors.fill: parent; onClicked: {} }

            // ── the card ──
            Rectangle {
                id: card
                readonly property bool below: !overlay.hasTarget || overlay.target.y < overlay.height / 2
                width: 440; height: col.implicitHeight + 40
                radius: 18
                color: root.darkMode ? Qt.rgba(0.16, 0.16, 0.17, 0.96) : Qt.rgba(0.98, 0.98, 0.99, 0.97)
                border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                x: {
                    if (!overlay.hasTarget) return (parent.width - width) / 2;
                    var cx = overlay.target.x + overlay.target.width / 2 - width / 2;
                    return Math.max(24, Math.min(parent.width - width - 24, cx));
                }
                y: !overlay.hasTarget ? (parent.height - height) / 2
                   : below ? overlay.target.y + overlay.target.height + 22
                           : overlay.target.y - height - 22
                Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
                Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
                Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.9; shadowOpacity: 0.45; shadowVerticalOffset: 10 }
                readonly property color fg: root.darkMode ? "#F5F5F7" : "#1D1D1F"
                readonly property color fg2: root.darkMode ? Qt.rgba(1, 1, 1, 0.68) : Qt.rgba(0, 0, 0, 0.62)

                Column {
                    id: col
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 10
                    // FreeForm mark on the first and last cards
                    Rectangle {
                        visible: root.step === 0 || root.step === root.steps.length - 1
                        width: 56; height: 56; radius: 14
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(root.accent, 1.25) }
                            GradientStop { position: 1; color: "#AF52DE" }
                        }
                        Text { anchors.centerIn: parent; text: "FF"; color: "white"; font.family: root.fam; font.pixelSize: 24; font.weight: Font.Black }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: I18n.tr(root.cur.title)
                        color: card.fg; font.family: root.fam; font.pixelSize: 20; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: I18n.tr(root.cur.body)
                        color: card.fg2; font.family: root.fam; font.pixelSize: 14; lineHeight: 1.15
                    }
                    Item { width: 1; height: 2 }
                    // progress dots
                    Row {
                            spacing: 6
                            Repeater {
                                model: root.steps.length
                                delegate: Rectangle {
                                    required property int index
                                    width: index === root.step ? 16 : 6; height: 6; radius: 3
                                    color: index === root.step ? root.accent : Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.25)
                                    Behavior on width { NumberAnimation { duration: 250 } }
                                }
                            }
                    }
                    Item {
                        width: parent.width; height: 30
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            component Btn: Rectangle {
                                id: b
                                property string label: ""
                                property bool primary: false
                                signal clicked()
                                width: bt.implicitWidth + 28; height: 30; radius: 15
                                color: primary ? (bma.pressed ? Qt.darker(root.accent, 1.15) : root.accent)
                                               : (bma.pressed ? Qt.rgba(0.5, 0.5, 0.5, 0.4) : Qt.rgba(0.5, 0.5, 0.5, 0.2))
                                Text { id: bt; anchors.centerIn: parent; text: b.label; color: b.primary ? "white" : card.fg; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MouseArea { id: bma; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
                            }
                            Btn { visible: root.step < root.steps.length - 1; label: I18n.tr("Skip Tour"); onClicked: root.stop() }
                            Btn { visible: root.step > 0; label: I18n.tr("Back"); onClicked: root.back() }
                            Btn { visible: !!root.cur.action; label: I18n.tr(root.cur.actionText || ""); onClicked: root.doAction(root.cur.action) }
                            Btn {
                                primary: true
                                label: root.step === 0 ? I18n.tr("Start") : root.step === root.steps.length - 1 ? I18n.tr("Done") : I18n.tr("Next")
                                onClicked: root.next()
                            }
                        }
                    }
                }
            }
        }
    }

    // while the user tries something out: a small pill under the menu bar to come back
    PanelWindow {
        screen: overlay.screen
        visible: root.running && root.paused
        anchors { top: true }
        margins { top: (root.bar ? root.bar.barHeight : 28) + 10 }
        implicitWidth: pill.width + 20; implicitHeight: 52
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "freeform-tour-pill"
        Rectangle {
            id: pill
            x: 10; y: 6
            width: pillRow.implicitWidth + 32; height: 38; radius: 19
            color: root.accent
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.7; shadowOpacity: 0.4; shadowVerticalOffset: 4 }
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 8
                Text { text: I18n.tr("Continue Tour"); color: "white"; font.family: root.fam; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text { text: "\u203A"; color: "white"; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resume() }
        }
    }
}
