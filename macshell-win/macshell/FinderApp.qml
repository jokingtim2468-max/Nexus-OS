// Finder (FreeForm) — a macOS-style file browser over your real folders (Windows and Linux).
//
//   qs -c MacShell ipc call finder open            qs ... ipc call finder show <folder>
//
// Sidebar favourites + drives, back/forward, icon or list view, search in the folder, Quick Look-
// style image thumbnails. Double-click opens a file in its usual app. Right-click: Open, Show in
// Explorer, Copy Path, Move to Recycle Bin (never deletes outright), New Folder.
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool dark: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property bool windows: Qt.platform.os === "windows"
    readonly property string home: String(Quickshell.env("USERPROFILE") || Quickshell.env("HOME") || "").split(String.fromCharCode(92)).join("/")

    property string folder: home
    property var backStack: []
    property var fwdStack: []
    property bool listView: false
    property string query: ""
    property var drives: []                       // ["C:/", "D:/"] (Windows) or mount points
    property string menuFor: ""                   // path the context menu is for ("" = the folder itself)
    property point menuAt: Qt.point(0, 0)
    property bool menuOpen: false
    property string status: ""

    function url(p) { return "file:///" + String(p).replace(/^\/+/, ""); }
    function nativePath(p) { return windows ? String(p).split("/").join(String.fromCharCode(92)) : p; }
    function nameOf(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i >= 0 && i < s.length - 1 ? s.substring(i + 1) : s; }
    function parentOf(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i > 0 ? s.substring(0, i) + (i === 2 && windows ? "/" : "") : (windows ? s : "/"); }

    function open(path) {
        if (path) go(String(path).split(String.fromCharCode(92)).join("/"), true);
        win.visible = true; win.raise(); win.requestActivate();
        if (drives.length === 0) drivesProc.running = true;
    }
    function close() { win.visible = false; }
    function go(path, record) {
        if (!path || path === folder) return;
        if (record) { backStack = backStack.concat([folder]); fwdStack = []; }
        folder = path; query = ""; menuOpen = false;
    }
    function back() { if (!backStack.length) return; fwdStack = fwdStack.concat([folder]); folder = backStack[backStack.length - 1]; backStack = backStack.slice(0, -1); }
    function forward() { if (!fwdStack.length) return; backStack = backStack.concat([folder]); folder = fwdStack[fwdStack.length - 1]; fwdStack = fwdStack.slice(0, -1); }
    function activate(path, isDir) { if (isDir) go(path, true); else Qt.openUrlExternally(url(path)); }

    // ── file actions ──
    function reveal(path) {
        if (windows) Quickshell.execDetached(["explorer.exe", "/select," + nativePath(path)]);
        else Qt.openUrlExternally(url(parentOf(path)));
    }
    function trash(path) {
        // the Recycle Bin / Trash, never a permanent delete
        if (windows) Quickshell.execDetached(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
            "Add-Type -AssemblyName Microsoft.VisualBasic; $p = '" + nativePath(path).replace(/'/g, "''") + "'; "
            + "if (Test-Path -LiteralPath $p -PathType Container) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin') } "
            + "else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }"]);
        else Quickshell.execDetached(["gio", "trash", path]);
        status = I18n.tr("Moved to the Recycle Bin: ") + nameOf(path);
    }
    function newFolder() {
        var base = folder.replace(/\/+$/, "") + "/" + I18n.tr("New Folder"), p = base;
        for (var n = 2; n < 50 && existing(p); n++) p = base + " " + n;
        if (windows) Quickshell.execDetached(["cmd.exe", "/c", "mkdir", nativePath(p)]);
        else Quickshell.execDetached(["mkdir", "-p", p]);
    }
    function existing(p) { for (var i = 0; i < files.count; i++) if (files.get(i, "filePath") === p) return true; return false; }
    function copyPath(p) { Quickshell.clipboardText = nativePath(p); status = I18n.tr("Path copied"); }

    // Windows drives / Linux mounts for the sidebar
    Process {
        id: drivesProc
        command: root.windows
            ? ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root }"]
            : ["sh", "-c", "findmnt -rno TARGET -t ext4,btrfs,xfs,vfat,exfat,ntfs,ntfs3,fuseblk 2>/dev/null | head -n 8"]
        stdout: StdioCollector {
            onStreamFinished: root.drives = text.split(/\r?\n/).filter(function (l) { return l.trim().length > 0; })
                                               .map(function (l) { return l.trim().split(String.fromCharCode(92)).join("/"); })
        }
    }

    FolderListModel {
        id: files
        folder: root.url(root.folder)
        showDirsFirst: true
        showHidden: false
        showDotAndDotDot: false
        sortCaseSensitive: false
        nameFilters: root.query.trim() !== "" ? ["*" + root.query.trim() + "*"] : []
        caseSensitive: false
    }

    readonly property var favourites: [
        { n: "Home", p: home, g: "smile" },
        { n: "Desktop", p: home + "/Desktop", g: "monitor" },
        { n: "Documents", p: home + "/Documents", g: "doc" },
        { n: "Downloads", p: home + "/Downloads", g: "return" },
        { n: "Pictures", p: home + "/Pictures", g: "photo" },
        { n: "Music", p: home + "/Music", g: "note" },
        { n: "Videos", p: home + "/Videos", g: "play" }
    ]
    readonly property var imageExt: ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg"]
    function extOf(name) { var i = String(name).lastIndexOf("."); return i > 0 ? String(name).substring(i + 1).toLowerCase() : ""; }
    function sizeText(b) { if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"; return (b / 1073741824).toFixed(2) + " GB"; }

    Window {
        id: win
        title: "Finder"
        width: 1000; height: 640
        minimumWidth: 720; minimumHeight: 420
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        QtObject {
            id: pal
            readonly property var preset: root.dock && root.dock.themePreset && root.dock.themePreset !== "default"
                                          ? root.dock.themePresets.filter(function (t) { return t.id === root.dock.themePreset; })[0] : null
            readonly property color bg: preset ? preset.bg : (root.dark ? "#1E1E1E" : "#FFFFFF")
            readonly property color side: preset ? preset.card : (root.dark ? "#262628" : "#F2F2F4")
            readonly property color text: root.dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: root.dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            readonly property color sep: root.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            readonly property color sel: root.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)
            readonly property color field: root.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color border: root.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
        }

        // a macOS-blue folder
        component FolderIcon: Item {
            property real s: 64
            width: s; height: s * 0.8
            Rectangle { x: 0; y: 0; width: parent.width * 0.42; height: parent.height * 0.25; radius: parent.s * 0.06; color: "#3D8FE0" }
            Rectangle { y: parent.height * 0.12; width: parent.width; height: parent.height * 0.88; radius: parent.s * 0.08; color: "#5AA9F5"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height * 0.75; radius: parent.radius; color: "#69B4F8" } }
        }
        // a document with its extension
        component DocIcon: Item {
            property real s: 64
            property string ext: ""
            width: s * 0.78; height: s
            Rectangle { anchors.fill: parent; radius: s * 0.06; color: "#FFFFFF"; border.width: 1; border.color: "#D0D0D5" }
            Rectangle { visible: ext !== ""; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height * 0.62; width: parent.width * 0.8; height: parent.height * 0.2; radius: 3; color: root.accent
                Text { anchors.centerIn: parent; text: ext.toUpperCase().substring(0, 4); color: "white"; font.family: root.fam; font.pixelSize: Math.max(7, s * 0.13); font.weight: Font.Bold } }
        }
        component FileIcon: Item {
            id: fi
            property string path: ""
            property string name: ""
            property bool isDir: false
            property real s: 64
            width: s; height: s
            readonly property bool isImage: !isDir && root.imageExt.indexOf(root.extOf(name)) >= 0
            FolderIcon { visible: fi.isDir; s: fi.s; anchors.centerIn: parent }
            DocIcon { visible: !fi.isDir && !fi.isImage; s: fi.s; ext: root.extOf(fi.name); anchors.centerIn: parent }
            Image {
                visible: fi.isImage
                anchors.fill: parent
                source: fi.isImage ? root.url(fi.path) : ""
                sourceSize: Qt.size(fi.s * 2, fi.s * 2)
                fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12; color: pal.bg; clip: true
            border.width: 1; border.color: pal.border

            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // ── sidebar ──
            Rectangle {
                id: side
                width: 200; height: parent.height; color: pal.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Row {
                    x: 16; y: 16; spacing: 8
                    Repeater {
                        model: ["#FF5F57", "#FEBC2E", "#28C840"]
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: 12; height: 12; radius: 6; color: modelData
                            MouseArea { anchors.fill: parent; onClicked: { if (parent.index === 0) root.close(); else if (parent.index === 1) win.showMinimized(); else win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized(); } }
                        }
                    }
                }
                Column {
                    x: 8; y: 48; width: parent.width - 16; spacing: 2
                    Text { x: 10; text: I18n.tr("Favourites"); color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold; bottomPadding: 4 }
                    Repeater {
                        model: root.favourites
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width; height: 28; radius: 6
                            color: root.folder === modelData.p ? pal.sel : "transparent"
                            WGlyph { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: parent.modelData.g; color: root.accent }
                            Text { x: 34; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.modelData.n); color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; onClicked: root.go(parent.modelData.p, true) }
                        }
                    }
                    Text { x: 10; text: I18n.tr("Locations"); color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold; topPadding: 12; bottomPadding: 4 }
                    Repeater {
                        model: root.drives
                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width; height: 28; radius: 6
                            color: root.folder === modelData ? pal.sel : "transparent"
                            WGlyph { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: "layers"; color: pal.text2 }
                            Text { x: 34; anchors.verticalCenter: parent.verticalCenter; text: root.windows ? I18n.tr("Disk ") + parent.modelData.replace(/\/$/, "") : parent.modelData; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                            MouseArea { anchors.fill: parent; onClicked: root.go(parent.modelData, true) }
                        }
                    }
                }
            }

            // ── toolbar ──
            Rectangle {
                id: bar
                x: side.width; width: parent.width - side.width; height: 52; color: pal.bg
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Row {
                    x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    Repeater {
                        model: [{ g: "\u2039", f: function () { root.back(); }, on: function () { return root.backStack.length > 0; } },
                                { g: "\u203A", f: function () { root.forward(); }, on: function () { return root.fwdStack.length > 0; } }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 28; height: 28; radius: 6; color: nb.containsMouse ? pal.sel : "transparent"
                            Text { anchors.centerIn: parent; text: parent.modelData.g; color: pal.text; opacity: (root.backStack, root.fwdStack, parent.modelData.on()) ? 1 : 0.3; font.pixelSize: 24 }
                            MouseArea { id: nb; anchors.fill: parent; hoverEnabled: true; onClicked: parent.modelData.f() }
                        }
                    }
                    Text { leftPadding: 8; anchors.verticalCenter: parent.verticalCenter; text: root.nameOf(root.folder) || root.folder; color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.Bold; width: Math.min(implicitWidth, bar.width - 420); elide: Text.ElideRight }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Repeater {
                        model: [{ id: false, t: "\u25A6" }, { id: true, t: "\u2630" }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 30; height: 26; radius: 6; color: root.listView === modelData.id ? pal.sel : "transparent"
                            Text { anchors.centerIn: parent; text: parent.modelData.t; color: pal.text; font.pixelSize: 15 }
                            MouseArea { anchors.fill: parent; onClicked: root.listView = parent.modelData.id }
                        }
                    }
                    Rectangle {
                        width: 200; height: 28; radius: 7; color: pal.field
                        WGlyph { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; kind: "search"; color: pal.text2 }
                        TextInput {
                            id: searchInput
                            x: 28; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter
                            color: pal.text; font.family: root.fam; font.pixelSize: 13; clip: true
                            onTextChanged: root.query = text
                            Connections { target: root; function onFolderChanged() { searchInput.text = ""; } }
                            Text { visible: searchInput.text === ""; text: I18n.tr("Search"); color: pal.text2; font: searchInput.font }
                        }
                    }
                }
            }

            // ── the folder ──
            Item {
                id: area
                x: side.width; y: bar.height; width: parent.width - side.width; height: parent.height - bar.height - 26

                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.RightButton | Qt.LeftButton
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) { root.menuFor = ""; root.menuAt = Qt.point(mouse.x, mouse.y); root.menuOpen = true; } else root.menuOpen = false; }
                }
                Text {
                    anchors.centerIn: parent
                    visible: files.status === FolderListModel.Ready && files.count === 0
                    text: root.query !== "" ? I18n.tr("No matches") : I18n.tr("This folder is empty")
                    color: pal.text2; font.family: root.fam; font.pixelSize: 14
                }

                GridView {
                    id: grid
                    visible: !root.listView
                    anchors.fill: parent; anchors.margins: 14
                    clip: true; model: files
                    cellWidth: 112; cellHeight: 112
                    delegate: Item {
                        id: gcell
                        required property string fileName
                        required property string filePath
                        required property bool fileIsDir
                        width: grid.cellWidth; height: grid.cellHeight
                        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 8; color: gma.containsMouse ? pal.sel : "transparent" }
                        FileIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 8; s: 58; path: gcell.filePath; name: gcell.fileName; isDir: gcell.fileIsDir }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 72; width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                            text: gcell.fileName; color: pal.text; font.family: root.fam; font.pixelSize: 12
                        }
                        MouseArea {
                            id: gma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: root.activate(gcell.filePath, gcell.fileIsDir)
                            onClicked: mouse => { if (mouse.button === Qt.RightButton) { root.menuFor = gcell.filePath; root.menuAt = mapToItem(area, mouse.x, mouse.y); root.menuOpen = true; } else root.menuOpen = false; }
                        }
                    }
                }
                ListView {
                    id: list
                    visible: root.listView
                    anchors.fill: parent; anchors.margins: 10
                    clip: true; model: files
                    header: Item {
                        width: list.width; height: 26
                        Text { x: 40; text: I18n.tr("Name"); color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Text { x: list.width - 300; text: I18n.tr("Date Modified"); color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Text { x: list.width - 100; text: I18n.tr("Size"); color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                    delegate: Rectangle {
                        id: lr
                        required property string fileName
                        required property string filePath
                        required property bool fileIsDir
                        required property var fileModified
                        required property var fileSize
                        required property int index
                        width: list.width; height: 30; radius: 6
                        color: lma.containsMouse ? pal.sel : (index % 2 ? Qt.rgba(pal.sel.r, pal.sel.g, pal.sel.b, pal.sel.a * 0.4) : "transparent")
                        FileIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; s: 20; path: lr.filePath; name: lr.fileName; isDir: lr.fileIsDir }
                        Text { x: 40; width: list.width - 360; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: lr.fileName; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                        Text { x: list.width - 300; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDateTime(lr.fileModified, "d MMM yyyy, h:mm AP"); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Text { x: list.width - 100; anchors.verticalCenter: parent.verticalCenter; text: lr.fileIsDir ? "--" : root.sizeText(lr.fileSize); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        MouseArea {
                            id: lma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: root.activate(lr.filePath, lr.fileIsDir)
                            onClicked: mouse => { if (mouse.button === Qt.RightButton) { root.menuFor = lr.filePath; root.menuAt = mapToItem(area, mouse.x, mouse.y); root.menuOpen = true; } else root.menuOpen = false; }
                        }
                    }
                }

                // ── right-click menu ──
                Rectangle {
                    visible: root.menuOpen
                    x: Math.min(root.menuAt.x, area.width - width - 6); y: Math.min(root.menuAt.y, area.height - height - 6)
                    width: 210; height: menuCol.height + 10; radius: 9
                    color: root.dark ? "#2C2C2E" : "#FFFFFF"; border.width: 1; border.color: pal.border
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.35; shadowVerticalOffset: 4 }
                    Column {
                        id: menuCol
                        x: 5; y: 5; width: parent.width - 10
                        Repeater {
                            model: root.menuFor !== ""
                                ? [{ t: "Open", f: function () { root.activate(root.menuFor, false); } },
                                   { t: root.windows ? "Show in Explorer" : "Show in Folder", f: function () { root.reveal(root.menuFor); } },
                                   { t: "Copy Path", f: function () { root.copyPath(root.menuFor); } },
                                   { t: "Move to Recycle Bin", f: function () { root.trash(root.menuFor); }, warn: true }]
                                : [{ t: "New Folder", f: function () { root.newFolder(); } },
                                   { t: root.windows ? "Open in Explorer" : "Open in Files", f: function () { Qt.openUrlExternally(root.url(root.folder)); } },
                                   { t: "Copy Path", f: function () { root.copyPath(root.folder); } }]
                            delegate: Rectangle {
                                required property var modelData
                                width: menuCol.width; height: 28; radius: 5
                                color: mma.containsMouse ? root.accent : "transparent"
                                Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.modelData.t); color: mma.containsMouse ? "white" : (parent.modelData.warn ? "#FF453A" : pal.text); font.family: root.fam; font.pixelSize: 13 }
                                MouseArea { id: mma; anchors.fill: parent; hoverEnabled: true; onClicked: { root.menuOpen = false; parent.modelData.f(); } }
                            }
                        }
                    }
                }
            }

            // ── status bar ──
            Rectangle {
                x: side.width; anchors.bottom: parent.bottom; width: parent.width - side.width; height: 26; color: pal.bg
                Rectangle { width: parent.width; height: 1; color: pal.sep }
                Text {
                    anchors.centerIn: parent
                    text: root.status !== "" ? root.status : files.count + (files.count === 1 ? I18n.tr(" item") : I18n.tr(" items"))
                    color: pal.text2; font.family: root.fam; font.pixelSize: 11
                }
                Timer { running: root.status !== ""; interval: 3000; onTriggered: root.status = "" }
            }
        }
    }
}
