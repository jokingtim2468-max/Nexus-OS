// File Explorer (FreeForm) — a File Explorer-style browser over your real folders, on glass:
// the window itself is see-through (Windows 11 acrylic blur behind it); only text and icons are drawn.
//
//   qs -c MacShell ipc call finder open            qs ... ipc call finder show <folder>
//
// Title bar with Windows caption buttons; back / forward / up / refresh, a clickable address bar
// and search; a command bar (New folder, Open, Copy path, Delete, view); navigation pane (Quick
// access + This PC drives); Details or Large icons view; status bar. Double-click opens a file in
// its usual app. Right-click: Open, Show in Explorer, Copy Path, Move to Recycle Bin, New Folder.
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
    property bool listView: true                 // Details view first, like File Explorer
    property string query: ""
    property var drives: []                       // ["C:/", "D:/"] (Windows) or mount points
    property string menuFor: ""                   // path the context menu is for ("" = the folder itself)
    property point menuAt: Qt.point(0, 0)
    property bool menuOpen: false
    property string status: ""
    property string selected: ""                  // the clicked file / folder
    // the address bar, as clickable pieces: [{ n: "C:", p: "C:/" }, { n: "Users", p: "C:/Users" }, ...]
    readonly property var crumbs: {
        var s = String(folder).replace(/\/+$/, ""), parts = s.split("/"), out = [], acc = "";
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] === "" && i === 0) { acc = "/"; out.push({ n: "/", p: "/" }); continue; }
            if (parts[i] === "") continue;
            acc = i === 0 ? parts[i] + "/" : (acc.replace(/\/$/, "") + "/" + parts[i]);
            out.push({ n: i === 0 && windows ? parts[i] : parts[i], p: acc });
        }
        return out;
    }
    function up() { var p = parentOf(folder); if (p && p !== folder) go(p, true); }
    // a themed icon (the Mac icon set) for a folder or file type, "" if the theme has none
    function themedIcon(name, isDir) {
        if (isDir) {
            var n = String(name).toLowerCase();
            var map = { desktop: "user-desktop", documents: "folder-documents", downloads: "folder-download", pictures: "folder-pictures",
                        music: "folder-music", videos: "folder-videos" };
            return Quickshell.iconPath(map[n] || "folder", true) || Quickshell.iconPath("folder", true);
        }
        var e = extOf(name);
        var mime = { pdf: "application-pdf", zip: "application-zip", exe: "application-x-executable", txt: "text-x-generic", md: "text-x-generic",
                     mp3: "audio-x-generic", wav: "audio-x-generic", mp4: "video-x-generic", mkv: "video-x-generic", doc: "x-office-document",
                     docx: "x-office-document", xls: "x-office-spreadsheet", xlsx: "x-office-spreadsheet", ppt: "x-office-presentation",
                     pptx: "x-office-presentation", html: "text-html", json: "text-x-script", py: "text-x-python", js: "text-x-script" }[e];
        return mime ? Quickshell.iconPath(mime, true) : "";
    }
    function typeText(name, isDir) { if (isDir) return I18n.tr("File folder"); var e = extOf(name); return e ? e.toUpperCase() + I18n.tr(" File") : I18n.tr("File"); }

    function url(p) { return "file:///" + String(p).replace(/^\/+/, ""); }
    function nativePath(p) { return windows ? String(p).split("/").join(String.fromCharCode(92)) : p; }
    function nameOf(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i >= 0 && i < s.length - 1 ? s.substring(i + 1) : s; }
    function parentOf(p) { var s = String(p).replace(/\/+$/, ""); var i = s.lastIndexOf("/"); return i > 0 ? s.substring(0, i) + (i === 2 && windows ? "/" : "") : (windows ? s : "/"); }

    function open(path) {
        if (path) go(String(path).split(String.fromCharCode(92)).join("/"), true);
        if (!win.visible) {                                             // fully on screen, below the menu bar
            var sc = Quickshell.screens.length ? Quickshell.screens[0] : null;
            if (sc) { win.width = Math.min(win.width, sc.width - 40); win.height = Math.min(win.height, sc.height - 124);
                      win.x = Math.round((sc.width - win.width) / 2); win.y = Math.round(34 + (sc.height - 124 - win.height) / 2); }
        }
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
        { n: "Home", p: home, g: "smile", i: "user-home" },
        { n: "Desktop", p: home + "/Desktop", g: "monitor", i: "user-desktop" },
        { n: "Documents", p: home + "/Documents", g: "doc", i: "folder-documents" },
        { n: "Downloads", p: home + "/Downloads", g: "return", i: "folder-download" },
        { n: "Pictures", p: home + "/Pictures", g: "photo", i: "folder-pictures" },
        { n: "Music", p: home + "/Music", g: "note", i: "folder-music" },
        { n: "Videos", p: home + "/Videos", g: "play", i: "folder-videos" }
    ]
    readonly property var imageExt: ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg"]
    function extOf(name) { var i = String(name).lastIndexOf("."); return i > 0 ? String(name).substring(i + 1).toLowerCase() : ""; }
    function sizeText(b) { if (b < 1024) return b + " B"; if (b < 1048576) return (b / 1024).toFixed(0) + " KB"; if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"; return (b / 1073741824).toFixed(2) + " GB"; }

    Window {
        id: win
        title: "File Explorer"
        width: 1100; height: 680
        minimumWidth: 760; minimumHeight: 440
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        // see-through: Windows 11's acrylic blur behind the window, nothing painted but text and icons
        property int ffBackdrop: 3
        property bool ffDarkGlass: root.dark

        QtObject {
            id: pal
            readonly property color text: root.dark ? "#FFFFFF" : "#111111"
            readonly property color text2: root.dark ? Qt.rgba(1, 1, 1, 0.66) : Qt.rgba(0, 0, 0, 0.6)
            readonly property color sep: root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
            readonly property color hover: root.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color sel: root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.1)
            readonly property color field: root.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
        }
        // drawn fallbacks when the icon theme has no icon for it
        component FolderIcon: Item {
            property real s: 64
            width: s; height: s * 0.8
            Rectangle { x: 0; y: 0; width: parent.width * 0.42; height: parent.height * 0.25; radius: parent.s * 0.06; color: "#3D8FE0" }
            Rectangle { y: parent.height * 0.12; width: parent.width; height: parent.height * 0.88; radius: parent.s * 0.08; color: "#5AA9F5"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height * 0.75; radius: parent.radius; color: "#69B4F8" } }
        }
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
            readonly property string themed: isImage ? "" : root.themedIcon(name, isDir)
            Image { visible: fi.themed !== ""; anchors.fill: parent; source: fi.themed; sourceSize: Qt.size(fi.s * 2, fi.s * 2); smooth: true; mipmap: true; asynchronous: true }
            FolderIcon { visible: fi.themed === "" && fi.isDir; s: fi.s; anchors.centerIn: parent }
            DocIcon { visible: fi.themed === "" && !fi.isDir && !fi.isImage; s: fi.s; ext: root.extOf(fi.name); anchors.centerIn: parent }
            Image {
                visible: fi.isImage
                anchors.fill: parent
                source: fi.isImage ? root.url(fi.path) : ""
                sourceSize: Qt.size(fi.s * 2, fi.s * 2)
                fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
            }
        }
        component IconBtn: Rectangle {
            id: ib
            property string glyph: ""
            property string label: ""
            property bool enabled2: true
            signal clicked()
            width: label !== "" ? lbl.implicitWidth + (glyph !== "" ? 40 : 20) : 34; height: 32; radius: 5
            color: ibMa.containsMouse && enabled2 ? pal.hover : "transparent"
            opacity: enabled2 ? 1 : 0.35
            Text { id: gl; visible: ib.glyph !== ""; x: ib.label !== "" ? 10 : (ib.width - width) / 2; anchors.verticalCenter: parent.verticalCenter; text: ib.glyph; color: pal.text; font.pixelSize: 16 }
            Text { id: lbl; visible: ib.label !== ""; x: ib.glyph !== "" ? 32 : 10; anchors.verticalCenter: parent.verticalCenter; text: ib.label; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
            MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; enabled: ib.enabled2; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
        }

        Rectangle {
            anchors.fill: parent
            radius: 8; clip: true
            // glass while it's a window; solid when maximized or fullscreen, so the desktop doesn't show through
            readonly property bool solid: win.visibility === Window.Maximized || win.visibility === Window.FullScreen
            color: solid ? (root.dark ? "#1C1C1C" : "#F3F3F3") : (root.dark ? Qt.rgba(0, 0, 0, 0.0) : Qt.rgba(1, 1, 1, 0.0))
            border.width: 1; border.color: pal.sep

            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // ── title bar: the folder's name, caption buttons ──
            Item {
                id: titleBar
                width: parent.width; height: 40
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized() }
                Row {
                    x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                    FileIcon { s: 18; isDir: true; name: root.nameOf(root.folder); anchors.verticalCenter: parent.verticalCenter }
                    Text { text: root.nameOf(root.folder) || root.folder; color: pal.text; font.family: root.fam; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                }
                WinCaption { window: win; dark: root.dark; anchors.top: parent.top; anchors.right: parent.right }
            }

            // ── navigation row: back, forward, up, refresh, address bar, search ──
            Item {
                id: navRow
                y: titleBar.height; width: parent.width; height: 44
                Row {
                    id: navBtns
                    x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    IconBtn { glyph: "\u2190"; enabled2: root.backStack.length > 0; onClicked: root.back() }
                    IconBtn { glyph: "\u2192"; enabled2: root.fwdStack.length > 0; onClicked: root.forward() }
                    IconBtn { glyph: "\u2191"; enabled2: root.parentOf(root.folder) !== root.folder; onClicked: root.up() }
                    IconBtn { glyph: "\u21BB"; onClicked: { var f = root.folder; files.folder = ""; files.folder = root.url(f); } }
                }
                // address bar: click a piece to jump there
                Rectangle {
                    x: navBtns.x + navBtns.width + 8; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - search.width - 24; height: 32; radius: 5; color: pal.field
                    border.width: 1; border.color: pal.sep
                    Flickable {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        contentWidth: crumbRow.width; clip: true; flickableDirection: Flickable.HorizontalFlick
                        Row {
                            id: crumbRow
                            height: parent.height; spacing: 0
                            Repeater {
                                model: root.crumbs
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    height: crumbRow.height
                                    Text { visible: parent.index > 0; text: "  \u203A  "; color: pal.text2; font.family: root.fam; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: ct.implicitWidth + 12; height: 24; radius: 4; color: cma.containsMouse ? pal.hover : "transparent"
                                        Text { id: ct; anchors.centerIn: parent; text: parent.parent.modelData.n; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                                        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: root.go(parent.parent.modelData.p, true) }
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    id: search
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 240; height: 32; radius: 5; color: pal.field
                    border.width: 1; border.color: searchInput.activeFocus ? root.accent : pal.sep
                    TextInput {
                        id: searchInput
                        x: 10; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter
                        color: pal.text; font.family: root.fam; font.pixelSize: 13; clip: true
                        onTextChanged: root.query = text
                        Connections { target: root; function onFolderChanged() { searchInput.text = ""; } }
                        Text { visible: searchInput.text === ""; text: I18n.tr("Search ") + (root.nameOf(root.folder) || ""); color: pal.text2; font: searchInput.font; width: parent.width; elide: Text.ElideRight }
                    }
                    WGlyph { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; kind: "search"; color: pal.text2 }
                }
            }

            // ── command bar ──
            Item {
                id: cmdBar
                y: navRow.y + navRow.height; width: parent.width; height: 44
                Rectangle { width: parent.width; height: 1; color: pal.sep }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                Row {
                    x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    IconBtn { glyph: "\u2795"; label: I18n.tr("New folder"); onClicked: root.newFolder() }
                    Rectangle { width: 1; height: 22; color: pal.sep; anchors.verticalCenter: parent.verticalCenter }
                    IconBtn { glyph: "\u2197"; label: I18n.tr("Open"); enabled2: root.selected !== ""; onClicked: root.activate(root.selected, false) }
                    IconBtn { glyph: "\u2398"; label: I18n.tr("Copy path"); onClicked: root.copyPath(root.selected !== "" ? root.selected : root.folder) }
                    IconBtn { glyph: "\uD83D\uDDD1"; label: I18n.tr("Delete"); enabled2: root.selected !== ""; onClicked: { root.trash(root.selected); root.selected = ""; } }
                    Rectangle { width: 1; height: 22; color: pal.sep; anchors.verticalCenter: parent.verticalCenter }
                    IconBtn { glyph: root.listView ? "\u2630" : "\u25A6"; label: root.listView ? I18n.tr("Details") : I18n.tr("Large icons"); onClicked: root.listView = !root.listView }
                }
                IconBtn {
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    visible: root.windows; label: I18n.tr("Open in Windows Explorer")
                    onClicked: Quickshell.execDetached(["explorer.exe", root.nativePath(root.folder)])
                }
            }

            // ── navigation pane ──
            Item {
                id: side
                y: cmdBar.y + cmdBar.height; width: 230; height: parent.height - y - statusBar.height
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                Flickable {
                    anchors.fill: parent; anchors.margins: 6; contentHeight: navCol.height; clip: true
                    Column {
                        id: navCol
                        width: parent.width; spacing: 1
                        Repeater {
                            model: root.favourites
                            delegate: Rectangle {
                                required property var modelData
                                width: navCol.width; height: 32; radius: 5
                                color: root.folder === modelData.p ? pal.sel : (fma.containsMouse ? pal.hover : "transparent")
                                Rectangle { visible: root.folder === parent.modelData.p; x: 0; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 16; radius: 1.5; color: root.accent }
                                Image {
                                    id: favIcon
                                    x: 12; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18
                                    source: Quickshell.iconPath(parent.modelData.i, true) || Quickshell.iconPath("folder", true); sourceSize: Qt.size(36, 36); smooth: true
                                }
                                Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.modelData.n); color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                                MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; onClicked: root.go(parent.modelData.p, true) }
                            }
                        }
                        Rectangle { width: navCol.width; height: 1; color: pal.sep }
                        Text { x: 12; topPadding: 8; bottomPadding: 4; text: root.windows ? I18n.tr("This PC") : I18n.tr("Locations"); color: pal.text2; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Repeater {
                            model: root.drives
                            delegate: Rectangle {
                                required property string modelData
                                width: navCol.width; height: 32; radius: 5
                                color: root.folder === modelData ? pal.sel : (dma.containsMouse ? pal.hover : "transparent")
                                Image { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; source: Quickshell.iconPath("drive-harddisk", true); sourceSize: Qt.size(36, 36); smooth: true }
                                Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: root.windows ? I18n.tr("Local Disk (") + parent.modelData.replace(/\/$/, "") + ")" : parent.modelData; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                                MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; onClicked: root.go(parent.modelData, true) }
                            }
                        }
                    }
                }
            }

            // ── the folder ──
            Item {
                id: area
                x: side.width; y: side.y; width: parent.width - side.width; height: side.height

                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.RightButton | Qt.LeftButton
                    onClicked: mouse => { root.selected = ""; if (mouse.button === Qt.RightButton) { root.menuFor = ""; root.menuAt = Qt.point(mouse.x, mouse.y); root.menuOpen = true; } else root.menuOpen = false; }
                }
                Text {
                    anchors.centerIn: parent
                    visible: files.status === FolderListModel.Ready && files.count === 0
                    text: root.query !== "" ? I18n.tr("No items match your search.") : I18n.tr("This folder is empty.")
                    color: pal.text2; font.family: root.fam; font.pixelSize: 14
                }

                // Details: Name | Date modified | Type | Size
                ListView {
                    id: list
                    visible: root.listView
                    anchors.fill: parent; anchors.margins: 8
                    clip: true; model: files
                    readonly property real cDate: width - 470
                    readonly property real cType: width - 270
                    readonly property real cSize: width - 110
                    header: Item {
                        width: list.width; height: 32
                        Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Name"); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Text { x: list.cDate; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Date modified"); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Text { x: list.cType; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Type"); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Text { x: list.cSize; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Size"); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                    }
                    delegate: Rectangle {
                        id: lr
                        required property string fileName
                        required property string filePath
                        required property bool fileIsDir
                        required property var fileModified
                        required property var fileSize
                        width: list.width; height: 32; radius: 4
                        color: root.selected === filePath ? pal.sel : (lma.containsMouse ? pal.hover : "transparent")
                        FileIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; s: 18; path: lr.filePath; name: lr.fileName; isDir: lr.fileIsDir }
                        Text { x: 38; width: list.cDate - 50; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: lr.fileName; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                        Text { x: list.cDate; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDateTime(lr.fileModified, "dd/MM/yyyy h:mm AP"); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Text { x: list.cType; width: 150; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: root.typeText(lr.fileName, lr.fileIsDir); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        Text { x: list.cSize; anchors.verticalCenter: parent.verticalCenter; text: lr.fileIsDir ? "" : root.sizeText(lr.fileSize); color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                        MouseArea {
                            id: lma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: root.activate(lr.filePath, lr.fileIsDir)
                            onClicked: mouse => { root.selected = lr.filePath; if (mouse.button === Qt.RightButton) { root.menuFor = lr.filePath; root.menuAt = mapToItem(area, mouse.x, mouse.y); root.menuOpen = true; } else root.menuOpen = false; }
                        }
                    }
                }
                // Large icons
                GridView {
                    id: grid
                    visible: !root.listView
                    anchors.fill: parent; anchors.margins: 10
                    clip: true; model: files
                    cellWidth: 118; cellHeight: 124
                    delegate: Item {
                        id: gcell
                        required property string fileName
                        required property string filePath
                        required property bool fileIsDir
                        width: grid.cellWidth; height: grid.cellHeight
                        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 6; color: root.selected === gcell.filePath ? pal.sel : (gma.containsMouse ? pal.hover : "transparent") }
                        FileIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 10; s: 64; path: gcell.filePath; name: gcell.fileName; isDir: gcell.fileIsDir }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 80; width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                            text: gcell.fileName; color: pal.text; font.family: root.fam; font.pixelSize: 12
                        }
                        MouseArea {
                            id: gma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: root.activate(gcell.filePath, gcell.fileIsDir)
                            onClicked: mouse => { root.selected = gcell.filePath; if (mouse.button === Qt.RightButton) { root.menuFor = gcell.filePath; root.menuAt = mapToItem(area, mouse.x, mouse.y); root.menuOpen = true; } else root.menuOpen = false; }
                        }
                    }
                }

                // ── right-click menu ──
                Rectangle {
                    visible: root.menuOpen
                    x: Math.min(root.menuAt.x, area.width - width - 6); y: Math.min(root.menuAt.y, area.height - height - 6)
                    width: 220; height: menuCol.height + 10; radius: 8
                    color: root.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.92) : Qt.rgba(0.98, 0.98, 0.98, 0.94); border.width: 1; border.color: pal.sep
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.35; shadowVerticalOffset: 4 }
                    Column {
                        id: menuCol
                        x: 5; y: 5; width: parent.width - 10
                        Repeater {
                            model: root.menuFor !== ""
                                ? [{ t: "Open", f: function () { root.activate(root.menuFor, false); } },
                                   { t: root.windows ? "Show in Explorer" : "Show in Folder", f: function () { root.reveal(root.menuFor); } },
                                   { t: "Copy as path", f: function () { root.copyPath(root.menuFor); } },
                                   { t: "Delete", f: function () { root.trash(root.menuFor); }, warn: true }]
                                : [{ t: "New folder", f: function () { root.newFolder(); } },
                                   { t: root.windows ? "Open in Windows Explorer" : "Open in Files", f: function () { Qt.openUrlExternally(root.url(root.folder)); } },
                                   { t: "Copy as path", f: function () { root.copyPath(root.folder); } }]
                            delegate: Rectangle {
                                required property var modelData
                                width: menuCol.width; height: 30; radius: 4
                                color: mma.containsMouse ? pal.hover : "transparent"
                                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.modelData.t); color: parent.modelData.warn ? "#FF6B5E" : pal.text; font.family: root.fam; font.pixelSize: 13 }
                                MouseArea { id: mma; anchors.fill: parent; hoverEnabled: true; onClicked: { root.menuOpen = false; parent.modelData.f(); } }
                            }
                        }
                    }
                }
            }

            // ── status bar ──
            Item {
                id: statusBar
                anchors.bottom: parent.bottom; width: parent.width; height: 28
                Rectangle { width: parent.width; height: 1; color: pal.sep }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: root.status !== "" ? root.status
                          : files.count + (files.count === 1 ? I18n.tr(" item") : I18n.tr(" items")) + (root.selected !== "" ? "   |   1 " + I18n.tr("item selected") : "")
                    color: pal.text2; font.family: root.fam; font.pixelSize: 12
                }
                Timer { running: root.status !== ""; interval: 3000; onTriggered: root.status = "" }
            }
        }
    }
}
