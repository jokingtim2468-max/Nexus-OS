"""Patch: hook FreeForm's own apps into MacShell's menus.

Applied after net_bt_windows.py (same engine: exact find -> replace, each must match once).

1. Apple menu: "App Store..." and "Welcome Tour..." under System Settings (AppStore.qml, Tutorial.qml).
2. Wallpaper Engine: Settings > Wallpaper lists your Steam Workshop wallpapers (animated
   previews); clicking one plays it through Wallpaper Engine, and the Liquid Glass refracts its
   preview. Picking a normal wallpaper afterwards closes Wallpaper Engine's. Not installed ->
   a "View on Steam" row (it's a paid Steam app; we only link to the store page).

    python compat/patches/freeform_apps.py          # apply (idempotent)
    python compat/patches/freeform_apps.py --check  # verify it is applied
"""
import sys

from net_bt_windows import apply

EDITS = {
    "MacBar.qml": [
        ('''            m.push(mi("System Settings\\u2026", "", function () { root.openSettings(); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { root.lockScreen(); }));''',
         '''            m.push(mi("System Settings\\u2026", "", function () { root.openSettings(); }));
            m.push(mi("App Store\\u2026", "", function () { if (hub && hub.appStore) hub.appStore.open(""); }));
            m.push(mi("Welcome Tour\\u2026", "", function () { if (hub && hub.tour) hub.tour.start(); }));
            m.push(mi("Widget Studio\\u2026", "", function () { if (hub && hub.widgetStudio) hub.widgetStudio.open(); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { root.lockScreen(); }));'''),
        # ── Wallpaper Engine state + apply ──
        ('''    function wpApply(path) {
        var pair = wpPairOf(path);''',
         '''    // ── Wallpaper Engine (FreeForm): Steam Workshop wallpapers, see compat/helper/wallpaper_engine.py ──
    property bool weInstalled: false
    property var weItems: []                 // { id, title, type, preview, file }
    property string weCurrent: ""            // project.json of the Wallpaper Engine wallpaper on screen
    function weRefresh() {
        if (!weStatusProc.running) weStatusProc.running = true;
        if (!weListProc.running) weListProc.running = true;
    }
    Process {
        id: weStatusProc
        command: ["macshell-helper", "wallpaper", "engine", "status"]
        stdout: StdioCollector { onStreamFinished: root.weInstalled = text.indexOf("installed") === 0 }
    }
    Process {
        id: weListProc
        command: ["macshell-helper", "wallpaper", "engine", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], lines = text.split("\\n");
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].replace(/\\r$/, "");
                    if (l.indexOf("W:") !== 0) continue;
                    var f = l.substring(2).split("\\t");
                    if (f.length >= 5) out.push({ id: f[0], title: f[1], type: f[2], preview: f[3], file: f[4] });
                }
                root.weItems = out;
            }
        }
    }
    // a local path (C:\\... on Windows, /home/... on Linux) as a file:// URL for Image
    function weUrl(p) { return p ? "file:///" + p.split(String.fromCharCode(92)).join("/").replace(/^\\/+/, "") : ""; }
    function weApply(w) {
        root.weCurrent = w.file;
        if (w.preview !== "") {                                              // the glass refracts its preview
            root.wallpaperPath = w.preview;
            try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = w.preview; } catch (e) {}
        }
        Quickshell.execDetached(["macshell-helper", "wallpaper", "engine", "apply", w.file]);
    }
    function wpApply(path) {
        if (root.weCurrent !== "") {                                         // a normal wallpaper replaces Wallpaper Engine's
            root.weCurrent = "";
            Quickshell.execDetached(["macshell-helper", "wallpaper", "engine", "stop"]);
        }
        var pair = wpPairOf(path);'''),
    ],
    "MacDock.qml": [
        # ── Settings > Wallpaper: Wallpaper Engine section ──
        ('''                Item {
                    width: parent.width; height: 30
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpapers"); topPadding: 0 }''',
         '''                // ── Wallpaper Engine (FreeForm) ──
                Item {
                    width: parent.width; height: 30
                    Component.onCompleted: if (root.bar) root.bar.weRefresh()
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpaper Engine"); topPadding: 0 }
                    SButton {
                        t: pal
                        visible: root.bar && root.bar.weItems.length > 0
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Workshop")
                        onClicked: Qt.openUrlExternally("steam://url/SteamWorkshopPage/431960")
                    }
                }
                SCard {
                    t: pal
                    visible: !(root.bar && root.bar.weItems.length > 0)
                    SRow {
                        t: pal
                        title: root.bar && root.bar.weInstalled ? I18n.tr("No Wallpaper Engine wallpapers yet") : I18n.tr("Wallpaper Engine")
                        subtitle: root.bar && root.bar.weInstalled ? I18n.tr("Subscribe to wallpapers in the Steam Workshop and they show up here.")
                                                                   : I18n.tr("Animated and interactive wallpapers from the Steam Workshop. A paid app on Steam.")
                        SButton {
                            t: pal
                            text: root.bar && root.bar.weInstalled ? I18n.tr("Open Workshop") : I18n.tr("View on Steam")
                            onClicked: Qt.openUrlExternally(root.bar && root.bar.weInstalled ? "steam://url/SteamWorkshopPage/431960" : "steam://store/431960")
                        }
                    }
                }
                GridView {
                    id: weGrid
                    visible: root.bar && root.bar.weItems.length > 0
                    width: parent.width
                    cellWidth: Math.floor((width - 20) / (width > 1100 ? 4 : 3))
                    cellHeight: Math.round(cellWidth * 0.5625) + 32
                    height: visible ? Math.min(contentHeight, cellHeight * 2) : 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.bar ? root.bar.weItems : []
                    delegate: Item {
                        id: we
                        required property var modelData
                        width: weGrid.cellWidth; height: weGrid.cellHeight
                        readonly property bool cur: root.bar && root.bar.weCurrent === modelData.file
                        readonly property bool gif: /\\.gif$/i.test(modelData.preview)
                        Item {
                            id: weBox
                            x: 5; y: 5
                            width: parent.width - 10; height: parent.height - 32
                            scale: weMa.pressed ? 0.98 : 1
                            Item {
                                id: weMask
                                anchors.fill: parent; visible: false
                                layer.enabled: true; layer.smooth: true
                                Rectangle { anchors.fill: parent; radius: 9; color: "black" }
                            }
                            Item {
                                anchors.fill: parent
                                layer.enabled: true; layer.smooth: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: weMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                Rectangle { anchors.fill: parent; color: pal.ctrl }
                                Image {
                                    anchors.fill: parent
                                    visible: we.modelData.preview !== ""
                                    source: root.bar ? root.bar.weUrl(we.modelData.preview) : ""
                                    sourceSize.width: 260
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; smooth: true
                                }
                                Loader {                                      // previews move while the pointer is on them
                                    anchors.fill: parent
                                    active: we.gif && weMa.containsMouse && prefsWindow.visible
                                    sourceComponent: AnimatedImage {
                                        source: root.bar ? root.bar.weUrl(we.modelData.preview) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: false; playing: true
                                    }
                                }
                                Rectangle {
                                    x: 6; y: 6
                                    width: weBadge.implicitWidth + 12; height: 18; radius: 9
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                    Text {
                                        id: weBadge
                                        anchors.centerIn: parent
                                        text: we.modelData.type === "video" ? I18n.tr("\\u25B6  Video") : we.modelData.type === "web" ? I18n.tr("Web") : I18n.tr("Scene")
                                        color: "white"; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 9; font.weight: Font.DemiBold
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: we.cur ? -3 : 0
                                radius: we.cur ? 12 : 9
                                color: "transparent"
                                border.width: we.cur ? 2.5 : 1
                                border.color: we.cur ? pal.accent : pal.cardBorder
                            }
                            MouseArea {
                                id: weMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.bar) root.bar.weApply(we.modelData)
                            }
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            x: 5; width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: we.modelData.title
                            color: we.cur ? pal.text : pal.text2
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                        }
                    }
                }

                Item {
                    width: parent.width; height: 30
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpapers"); topPadding: 0 }'''),
    ],
}

if __name__ == "__main__":
    sys.exit(0 if apply(check="--check" in sys.argv, edits_by_file=EDITS) else 1)
