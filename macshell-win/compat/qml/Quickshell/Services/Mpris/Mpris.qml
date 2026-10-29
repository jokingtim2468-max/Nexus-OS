pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mpris on Windows: one player per Windows media session (the apps in the Windows media overlay),
// fed by compat/helper/media.ps1 watch. Controls run media.ps1 <app> <action>.
Singleton {
    id: mpris
    readonly property string ps1dir: Quickshell.env("FREEFORM_HELPER") || ""
    readonly property var players: QtObject { property var values: mpris.list }
    property var list: []
    property var byId: ({})

    function run(id, args) {
        Quickshell.execDetached(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                                 "-File", ps1dir + "/media.ps1", id].concat(args));
    }

    component Player: QtObject {
        id: pl
        property string appId: ""
        property string identity: ""
        property string trackTitle: ""
        property string trackArtist: ""
        property string trackAlbum: ""
        property string trackArtUrl: ""
        property bool isPlaying: false
        property real position: 0
        property real length: 0
        property bool canGoNext: false
        property bool canGoPrevious: false
        property bool canSeek: false
        property bool canControl: true
        property bool canPlay: true
        property bool canPause: true
        property bool shuffle: false
        property int loopState: 0
        property real volume: 1
        property string desktopEntry: identity.toLowerCase()
        readonly property int playbackState: isPlaying ? 1 : 2
        function play() { isPlaying = true; mpris.run(appId, ["play"]); }
        function pause() { isPlaying = false; mpris.run(appId, ["pause"]); }
        function togglePlaying() { isPlaying = !isPlaying; mpris.run(appId, ["toggle"]); }
        function next() { mpris.run(appId, ["next"]); }
        function previous() { mpris.run(appId, ["previous"]); }
        function seek(offset) { position = Math.max(0, position + offset); mpris.run(appId, ["seek", String(position)]); }
        function setShuffle(on) { shuffle = on; mpris.run(appId, ["shuffle", on ? "on" : "off"]); }
        function setLoop(s) { loopState = s; mpris.run(appId, ["loop", ["none", "track", "playlist"][s] || "none"]); }
        function raise() {}
    }
    Component { id: playerComp; Player {} }
    property bool go: false
    Timer { interval: 2000; running: true; onTriggered: mpris.go = true }

    Process {
        id: watcher
        // started 2 s after FreeForm (helpers starting all at once can fail with 0xc0000142); restarts on exit
        running: mpris.ps1dir !== "" && mpris.go
        command: ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", mpris.ps1dir + "/media.ps1", "watch"]
        stdout: SplitParser {
            onRead: line => {
                var d; try { d = JSON.parse(line); } catch (e) { return; }
                var ps = d.players || [], seen = {}, out = [], map = mpris.byId;
                if (!Array.isArray(ps)) ps = [ps];
                for (var i = 0; i < ps.length; i++) {
                    var s = ps[i], p = map[s.id];
                    if (!p) { p = playerComp.createObject(mpris, { appId: s.id }); map[s.id] = p; }
                    p.identity = s.identity || ""; p.trackTitle = s.title || ""; p.trackArtist = s.artist || "";
                    p.trackAlbum = s.album || ""; p.trackArtUrl = s.art ? "file:///" + s.art.split("\\").join("/") : "";
                    p.isPlaying = !!s.playing; p.position = s.position || 0; p.length = s.length || 0;
                    p.canGoNext = !!s.canNext; p.canGoPrevious = !!s.canPrev; p.canSeek = !!s.canSeek;
                    p.shuffle = !!s.shuffle; p.loopState = s.loop === "Track" ? 1 : (s.loop === "List" ? 2 : 0);
                    seen[s.id] = true; out.push(p);
                }
                for (var k in map) if (!seen[k]) { map[k].destroy(); delete map[k]; }
                mpris.byId = map; mpris.list = out;
            }
        }
        onExited: restart.start()          // PowerShell died (sleep/resume, crash): start it again
    }
    Timer { id: restart; interval: 3000; onTriggered: watcher.running = true }
}
