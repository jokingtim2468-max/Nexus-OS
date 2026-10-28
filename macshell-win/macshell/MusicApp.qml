// Music — a macOS Music-style player for FreeForm.
//
//   qs -c MacShell ipc call music open
//
// Library: the music files in ~/Music (mp3, flac, m4a, aac, ogg, opus, wav), played here, offline,
// covers from cover/folder images in the album folder. Albums = folders; "Artist - Title" file names
// fill in the artist. Services: Spotify, Apple Music and SoundCloud play in their own apps or web
// players; whatever is playing there shows in the Now Playing area and is controlled from here
// (Windows media session / MPRIS). Colours follow the theme (Settings > Appearance > Theme).
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "I18n.js" as I18n

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#FA2D48"
    readonly property bool dark: dock ? dock.darkMode : true
    readonly property string home: Quickshell.env("HOME") || Quickshell.env("USERPROFILE")
    readonly property string musicDir: home + "/Music"

    property string page: "songs"          // listen | songs | albums | artists | album:<name> | sources
    property var songs: []                 // { path, title, artist, album, cover }
    property var queue: []
    property int qi: -1
    readonly property var current: qi >= 0 && qi < queue.length ? queue[qi] : null
    property bool shuffle: false
    property int repeat: 0                 // 0 off, 1 all, 2 one
    property string search: ""

    // what's playing in another app (Spotify, Apple Music, a browser with SoundCloud…)
    // the Spotify desktop app, when it's installed (Start Menu / Microsoft Store on Windows): used directly, no login here
    readonly property var spotifyApp: {
        var es = DesktopEntries.applications.values;
        for (var i = 0; i < es.length; i++) if (/^spotify/i.test(es[i].name || "")) return es[i];
        return null;
    }
    // Spotify first (playing, then paused), else any other playing app
    readonly property var other: {
        var ps = Mpris.players.values, best = null, spot = null;
        for (var i = 0; i < ps.length; i++) {
            if (/freeform|quickshell/i.test(ps[i].identity || "")) continue;
            var isSpot = /spotify/i.test(ps[i].identity || "");
            if (isSpot && ps[i].isPlaying) return ps[i];
            if (isSpot) spot = ps[i];
            else if (ps[i].isPlaying && !best) best = ps[i];
        }
        if (best) return best;
        if (spot) return spot;
        for (var j = 0; j < ps.length; j++) if (!/freeform|quickshell/i.test(ps[j].identity || "")) return ps[j];
        return null;
    }
    function openSpotify() { if (spotifyApp) spotifyApp.execute(); else Qt.openUrlExternally("https://open.spotify.com"); }
    readonly property bool localActive: player.playbackState !== MediaPlayer.StoppedState && current !== null
    readonly property string npTitle: localActive ? current.title : (other ? other.trackTitle || "" : "")
    readonly property string npArtist: localActive ? current.artist + (current.album ? " — " + current.album : "") : (other ? (other.trackArtist || "") + (other.identity ? " · " + other.identity : "") : "")
    readonly property string npArt: localActive ? current.cover : (other ? other.trackArtUrl || "" : "")
    readonly property bool npPlaying: localActive ? player.playbackState === MediaPlayer.PlayingState : (other ? other.isPlaying : false)
    readonly property real npPos: localActive ? player.position / 1000 : (other ? other.position : 0)
    readonly property real npLen: localActive ? player.duration / 1000 : (other ? other.length : 0)

    function open() { win.visible = true; win.raise(); win.requestActivate(); if (songs.length === 0) rescan(); }
    function close() { win.visible = false; }
    function url(p) { return p ? "file:///" + String(p).split(String.fromCharCode(92)).join("/").replace(/^\/+/, "") : ""; }
    function mmss(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ":" + ((s % 60) < 10 ? "0" : "") + (s % 60); }

    // ── library scan (macshell-helper wallpaper scan lists files; here: music files) ──
    function rescan() { if (!scan.running) scan.running = true; }
    Process {
        id: scan
        command: Qt.platform.os === "windows"
            ? ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
               "Get-ChildItem -LiteralPath $env:USERPROFILE\\Music -Recurse -File -Include *.mp3,*.flac,*.m4a,*.aac,*.ogg,*.opus,*.wav,*.jpg,*.jpeg,*.png | ForEach-Object { $_.FullName }"]
            : ["sh", "-c", "find -L \"$1\" -type f \\( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\) 2>/dev/null", "sh", root.musicDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var files = text.split(/\r?\n/).filter(function (l) { return l.length > 0; }).map(function (l) { return l.split(String.fromCharCode(92)).join("/"); });
                var covers = {}, out = [];
                files.forEach(function (f) {
                    if (/\.(jpe?g|png)$/i.test(f)) {
                        var dir = f.substring(0, f.lastIndexOf("/")), n = f.substring(f.lastIndexOf("/") + 1).toLowerCase();
                        if (!covers[dir] || /^(cover|folder|front|album)/.test(n)) covers[dir] = f;
                    }
                });
                files.forEach(function (f) {
                    if (/\.(jpe?g|png)$/i.test(f)) return;
                    var dir = f.substring(0, f.lastIndexOf("/")), base = f.substring(f.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
                    base = base.replace(/^\d+[\s._-]+/, "");                       // "01 - Title" -> "Title"
                    var artist = "", title = base, m = /^(.+?)\s+-\s+(.+)$/.exec(base);
                    if (m) { artist = m[1]; title = m[2]; }
                    var album = dir === root.musicDir ? "" : dir.substring(dir.lastIndexOf("/") + 1);
                    out.push({ path: f, title: title, artist: artist || I18n.tr("Unknown Artist"), album: album, cover: covers[dir] || "" });
                });
                out.sort(function (a, b) { return a.title.localeCompare(b.title); });
                root.songs = out;
            }
        }
    }
    readonly property var albums: {
        var m = {}, out = [];
        songs.forEach(function (s) { var k = s.album || I18n.tr("Singles"); if (!m[k]) { m[k] = { name: k, artist: s.artist, cover: s.cover, songs: [] }; out.push(m[k]); } m[k].songs.push(s); });
        return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
    }
    readonly property var artists: {
        var m = {}, out = [];
        songs.forEach(function (s) { if (!m[s.artist]) { m[s.artist] = { name: s.artist, cover: s.cover, count: 0 }; out.push(m[s.artist]); } m[s.artist].count++; });
        return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
    }
    readonly property var shownSongs: {
        var q = search.trim().toLowerCase(), l = songs;
        if (page.indexOf("album:") === 0) { var a = page.substring(6); l = l.filter(function (s) { return (s.album || I18n.tr("Singles")) === a; }); }
        if (page.indexOf("artist:") === 0) { var r = page.substring(7); l = l.filter(function (s) { return s.artist === r; }); }
        if (q) l = l.filter(function (s) { return (s.title + " " + s.artist + " " + s.album).toLowerCase().indexOf(q) >= 0; });
        return l;
    }

    // ── playback ──
    function playList(list, i) {
        if (!list.length) return;
        if (other && other.isPlaying) other.pause();
        queue = list.slice(); qi = i;
        player.source = url(current.path); player.play();
    }
    function toggle() {
        if (localActive || (current && !other)) { if (player.playbackState === MediaPlayer.PlayingState) player.pause(); else player.play(); }
        else if (other) other.togglePlaying();
        else if (shownSongs.length) playList(shownSongs, 0);
    }
    function next() {
        if (!localActive) { if (other) other.next(); return; }
        if (repeat === 2) { player.position = 0; player.play(); return; }
        var n = shuffle ? Math.floor(Math.random() * queue.length) : qi + 1;
        if (n >= queue.length) { if (repeat === 1) n = 0; else { player.stop(); return; } }
        qi = n; player.source = url(current.path); player.play();
    }
    function previous() {
        if (!localActive) { if (other) other.previous(); return; }
        if (player.position > 3000 || qi === 0) { player.position = 0; return; }
        qi--; player.source = url(current.path); player.play();
    }
    MediaPlayer {
        id: player
        audioOutput: AudioOutput { id: out; volume: 0.8 }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) root.next()
    }

    // ═════════════ WINDOW ═════════════
    Window {
        id: win
        title: "Music"
        width: 1100; height: 700
        minimumWidth: 860; minimumHeight: 520
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        QtObject {
            id: pal
            readonly property var preset: root.dock && root.dock.themePreset && root.dock.themePreset !== "default"
                                          ? root.dock.themePresets.filter(function (t) { return t.id === root.dock.themePreset; })[0] : null
            readonly property color bg: preset ? preset.bg : (root.dark ? "#1E1E1E" : "#FFFFFF")
            readonly property color side: preset ? preset.card : (root.dark ? "#262628" : "#F2F2F4")
            readonly property color bar: root.dark ? "#2A2A2C" : "#ECECEE"
            readonly property color text: preset ? preset.fg : (root.dark ? "#F5F5F7" : "#1D1D1F")
            readonly property color text2: root.dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            readonly property color sep: root.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
            readonly property color sel: root.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)
            readonly property color field: root.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
        }

        component Cover: Item {
            id: cv
            property string src: ""
            property real r: 6
            Rectangle { id: cvMask; anchors.fill: parent; radius: cv.r; visible: false; layer.enabled: true }
            Rectangle {
                anchors.fill: parent; radius: cv.r
                gradient: Gradient { GradientStop { position: 0; color: "#FC5C7D" } GradientStop { position: 1; color: "#6A82FB" } }
                WGlyph { anchors.centerIn: parent; width: parent.width * 0.38; height: width; kind: "note"; color: "white" }
            }
            Image {
                anchors.fill: parent
                source: cv.src.indexOf(":") > 1 || cv.src.indexOf("/") === 0 ? (cv.src.indexOf("file:") === 0 || cv.src.indexOf("http") === 0 ? cv.src : root.url(cv.src)) : ""
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                sourceSize: Qt.size(width * 2, height * 2)
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: cvMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
        }

        Rectangle {
            anchors.fill: parent; radius: 12; color: pal.bg; clip: true
            border.width: 1; border.color: root.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // ── sidebar ──
            Rectangle {
                id: side
                width: 230; height: parent.height; color: pal.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Row {
                    x: 18; y: 18; spacing: 8
                    Repeater { model: ["#FF5F57", "#FEBC2E", "#28C840"]; delegate: Rectangle { required property string modelData; required property int index; width: 14; height: 14; radius: 7; color: index !== 1 && win.active ? modelData : Qt.rgba(0.5, 0.5, 0.5, 0.35) } }
                }
                MouseArea { x: 16; y: 16; width: 20; height: 18; onClicked: win.visible = false }
                Rectangle {
                    x: 14; y: 48; width: parent.width - 28; height: 30; radius: 8; color: pal.field
                    WGlyph { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; kind: "search"; color: pal.text2 }
                    TextInput {
                        x: 30; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                        color: pal.text; font.family: root.fam; font.pixelSize: 13; clip: true
                        onTextEdited: { root.search = text; if (root.page !== "songs" && root.page.indexOf("album:") !== 0) root.page = "songs"; }
                        Text { visible: !parent.text; text: I18n.tr("Search"); color: pal.text2; font: parent.font }
                    }
                }
                Column {
                    x: 10; y: 92; width: parent.width - 20; spacing: 1
                    Repeater {
                        model: [{ h: "Apple Music" }, { id: "listen", t: "Listen Now", g: "play" },
                                { h: "Library" }, { id: "songs", t: "Songs", g: "note" }, { id: "albums", t: "Albums", g: "layers" }, { id: "artists", t: "Artists", g: "smile" },
                                { h: "Services" }, { id: "sources", t: "Spotify, Apple Music & SoundCloud", g: "link" }]
                        delegate: Item {
                            id: nav
                            required property var modelData
                            width: parent.width; height: modelData.h ? 30 : 30
                            Text { visible: !!nav.modelData.h; x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 4; text: I18n.tr(nav.modelData.h === "Apple Music" ? "Music" : (nav.modelData.h || "")); color: pal.text2; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Rectangle {
                                visible: !nav.modelData.h; anchors.fill: parent; radius: 7
                                color: root.page === nav.modelData.id ? pal.sel : "transparent"
                                WGlyph { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: nav.modelData.g || "note"; color: root.accent }
                                Text { x: 34; width: parent.width - 40; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(nav.modelData.t || ""); color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent; onClicked: root.page = nav.modelData.id }
                            }
                        }
                    }
                }
            }

            // ── toolbar with the "LCD" now-playing display, like macOS Music ──
            Rectangle {
                id: top
                x: side.width; width: parent.width - side.width; height: 64; color: pal.bg
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                Row {
                    x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 16
                    component Tb: Item {
                        id: tb
                        property string g: ""
                        property bool on: false
                        property real s: 18
                        signal clicked()
                        width: 28; height: 28
                        WGlyph { anchors.centerIn: parent; width: tb.s; height: tb.s; kind: tb.g; color: tb.on ? root.accent : pal.text }
                        MouseArea { anchors.fill: parent; onClicked: tb.clicked() }
                    }
                    Tb { g: "shuffle"; s: 14; on: root.shuffle; onClicked: root.shuffle = !root.shuffle }
                    Tb { g: "prev"; onClicked: root.previous() }
                    Tb { g: root.npPlaying ? "pause" : "play"; s: 22; onClicked: root.toggle() }
                    Tb { g: "next"; onClicked: root.next() }
                    Tb { g: root.repeat === 2 ? "repeat1" : "repeat"; s: 14; on: root.repeat > 0; onClicked: root.repeat = (root.repeat + 1) % 3 }
                }
                Rectangle {
                    id: lcd
                    anchors.centerIn: parent
                    width: Math.min(460, parent.width - 380); height: 46; radius: 6
                    color: root.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                    border.width: 1; border.color: pal.sep
                    Cover { x: 0; width: 46; height: 46; r: 6; src: root.npArt }
                    Column {
                        x: 56; width: parent.width - 66; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.npTitle || I18n.tr("Not Playing"); color: pal.text; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.npArtist; color: pal.text2; font.family: root.fam; font.pixelSize: 11 }
                        Item {
                            width: parent.width; height: 10
                            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.mmss(root.npPos); color: pal.text2; font.family: root.fam; font.pixelSize: 9 }
                            Rectangle {
                                anchors.centerIn: parent; width: parent.width - 70; height: 3; radius: 1.5; color: pal.sep
                                Rectangle { width: parent.width * (root.npLen > 0 ? Math.min(1, root.npPos / root.npLen) : 0); height: 3; radius: 1.5; color: pal.text2 }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -5
                                    onClicked: mouse => { var f = mouse.x / width; if (root.localActive) player.position = f * player.duration; else if (root.other && root.other.canSeek) root.other.position = f * root.other.length; }
                                }
                            }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "-" + root.mmss(root.npLen - root.npPos); color: pal.text2; font.family: root.fam; font.pixelSize: 9 }
                        }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    WGlyph { width: 14; height: 14; kind: "speaker"; color: pal.text2; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle {
                        width: 90; height: 4; radius: 2; color: pal.sep; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { width: parent.width * out.volume; height: 4; radius: 2; color: pal.text2 }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            function setFrom(x) { out.volume = Math.max(0, Math.min(1, x / width)); }
                            onPressed: mouse => setFrom(mouse.x)
                            onPositionChanged: mouse => setFrom(mouse.x)
                        }
                    }
                }
            }

            // ── content ──
            Flickable {
                id: content
                x: side.width; y: top.height; width: parent.width - side.width; height: parent.height - top.height
                contentHeight: body.height + 40; clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: body
                    x: 28; y: 22; width: content.width - 56; spacing: 14

                    Text {
                        text: root.page === "listen" ? I18n.tr("Listen Now") : root.page === "albums" ? I18n.tr("Albums") : root.page === "artists" ? I18n.tr("Artists")
                              : root.page === "sources" ? I18n.tr("Services") : root.page.indexOf("album:") === 0 ? root.page.substring(6)
                              : root.page.indexOf("artist:") === 0 ? root.page.substring(7) : I18n.tr("Songs")
                        color: pal.text; font.family: root.fam; font.pixelSize: 26; font.weight: Font.Bold
                    }

                    // empty library
                    Column {
                        visible: root.songs.length === 0 && root.page !== "sources"
                        spacing: 8
                        Text { text: I18n.tr("Your music library is empty"); color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { width: body.width; wrapMode: Text.WordWrap; text: I18n.tr("Put music files in your Music folder (") + root.musicDir + I18n.tr(") and they show up here, playable offline. Spotify, Apple Music and SoundCloud play in their own apps; see Services."); color: pal.text2; font.family: root.fam; font.pixelSize: 13 }
                        Rectangle { width: rs.implicitWidth + 28; height: 28; radius: 14; color: root.accent
                            Text { id: rs; anchors.centerIn: parent; text: I18n.tr("Scan Again"); color: "white"; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; onClicked: root.rescan() } }
                    }

                    // Listen Now: big album tiles
                    Flow {
                        visible: root.page === "listen" || root.page === "albums"
                        width: body.width; spacing: 22
                        Repeater {
                            model: root.page === "listen" ? root.albums.slice(0, 8) : (root.page === "albums" ? root.albums : [])
                            delegate: Column {
                                id: al
                                required property var modelData
                                width: root.page === "listen" ? 200 : 170; spacing: 6
                                Cover { width: parent.width; height: width; r: 8; src: al.modelData.cover
                                    MouseArea { anchors.fill: parent; onClicked: root.page = "album:" + al.modelData.name; onDoubleClicked: root.playList(al.modelData.songs, 0) } }
                                Text { width: parent.width; elide: Text.ElideRight; text: al.modelData.name; color: pal.text; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; text: al.modelData.artist; color: pal.text2; font.family: root.fam; font.pixelSize: 12 }
                            }
                        }
                    }

                    // Artists
                    Flow {
                        visible: root.page === "artists"
                        width: body.width; spacing: 22
                        Repeater {
                            model: root.page === "artists" ? root.artists : []
                            delegate: Column {
                                id: ar
                                required property var modelData
                                width: 140; spacing: 6
                                Cover { width: 140; height: 140; r: 70; src: ar.modelData.cover
                                    MouseArea { anchors.fill: parent; onClicked: root.page = "artist:" + ar.modelData.name } }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: ar.modelData.name; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                            }
                        }
                    }

                    // Songs table (also an album / artist page)
                    Column {
                        visible: root.page === "songs" || root.page.indexOf("album:") === 0 || root.page.indexOf("artist:") === 0
                        width: body.width
                        Repeater {
                            model: parent.visible ? root.shownSongs : []
                            delegate: Rectangle {
                                id: sr
                                required property var modelData
                                required property int index
                                readonly property bool playingThis: root.current && root.current.path === modelData.path
                                width: body.width; height: 40; radius: 6
                                color: srMa.containsMouse ? pal.sel : (index % 2 ? "transparent" : Qt.rgba(pal.sel.r, pal.sel.g, pal.sel.b, pal.sel.a * 0.4))
                                Cover { x: 8; width: 30; height: 30; r: 4; anchors.verticalCenter: parent.verticalCenter; src: sr.modelData.cover }
                                Text { x: 50; width: parent.width * 0.4; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: sr.modelData.title; color: sr.playingThis ? root.accent : pal.text; font.family: root.fam; font.pixelSize: 13; font.weight: sr.playingThis ? Font.DemiBold : Font.Normal }
                                Text { x: 50 + parent.width * 0.42; width: parent.width * 0.25; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: sr.modelData.artist; color: pal.text2; font.family: root.fam; font.pixelSize: 13 }
                                Text { x: 50 + parent.width * 0.69; width: parent.width * 0.25; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: sr.modelData.album; color: pal.text2; font.family: root.fam; font.pixelSize: 13 }
                                MouseArea { id: srMa; anchors.fill: parent; hoverEnabled: true; onDoubleClicked: root.playList(root.shownSongs, sr.index) }
                            }
                        }
                    }

                    // Services
                    Column {
                        visible: root.page === "sources"
                        width: body.width; spacing: 12
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: I18n.tr("These services play in their own apps or in your browser. Whatever plays there shows at the top of this window and the buttons control it.")
                            color: pal.text2; font.family: root.fam; font.pixelSize: 13
                        }
                        Repeater {
                            model: [
                                { n: "Spotify", d: "Open the Spotify app or open.spotify.com. Playlists, liked songs and offline downloads (Premium) live in Spotify.", c1: "#1ED760", c2: "#128C3E", app: "spotify:", url: "https://open.spotify.com" },
                                { n: "Apple Music", d: "On Windows: the Apple Music app from the App Store, or music.apple.com. Downloads for offline play work in the app with a subscription.", c1: "#FC5C7D", c2: "#FA233B", app: "", url: "https://music.apple.com" },
                                { n: "SoundCloud", d: "soundcloud.com in your browser. Offline listening and no ads come with SoundCloud Go+ in their mobile app.", c1: "#FF7700", c2: "#FF3300", app: "", url: "https://soundcloud.com" }
                            ]
                            delegate: Rectangle {
                                id: svc
                                required property var modelData
                                width: body.width; height: 92; radius: 12; color: pal.side
                                Rectangle { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 60; height: 60; radius: 14
                                    gradient: Gradient { GradientStop { position: 0; color: svc.modelData.c1 } GradientStop { position: 1; color: svc.modelData.c2 } }
                                    WGlyph { anchors.centerIn: parent; width: 26; height: 26; kind: "note"; color: "white" } }
                                Column {
                                    x: 92; width: parent.width - 92 - 140; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                    Text { text: svc.modelData.n + (root.other && new RegExp(svc.modelData.n.split(" ")[0], "i").test(root.other.identity || "") ? I18n.tr("  ·  playing now") : ""); color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { width: parent.width; wrapMode: Text.WordWrap; color: pal.text2; font.family: root.fam; font.pixelSize: 12
                                        text: svc.modelData.n === "Spotify" && root.spotifyApp ? I18n.tr("Spotify app found on this PC: it's used directly, no sign-in needed here. Whatever it plays shows at the top.") : I18n.tr(svc.modelData.d) }
                                }
                                Rectangle {
                                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                    width: ob.implicitWidth + 28; height: 28; radius: 14; color: root.accent
                                    Text { id: ob; anchors.centerIn: parent; text: I18n.tr("Open"); color: "white"; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    // spotify: opens the Spotify app when it's installed
                                    MouseArea { anchors.fill: parent; onClicked: svc.modelData.n === "Spotify" ? root.openSpotify() : Qt.openUrlExternally(svc.modelData.app || svc.modelData.url) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
