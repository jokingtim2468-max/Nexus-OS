// WidgetContext — live data and premade actions for custom widgets (Widget Studio).
//
// Data a widget's text can show with {tokens}: {title} {artist} {album} {player} {time} {time24}
// {date} {day} {battery} {volume}. Actions a button can run: see `actions` below. Works on Linux
// (MPRIS / PipeWire / UPower) and on Windows (the stand-ins in compat/qml).
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

QtObject {
    id: ctx
    property var hub: null

    // the player a widget controls: the one playing, else the first
    readonly property var player: {
        var ps = Mpris.players.values, best = null;
        for (var i = 0; i < ps.length; i++) { if (ps[i].isPlaying) return ps[i]; if (!best) best = ps[i]; }
        return best;
    }
    readonly property bool playing: player ? player.isPlaying : false
    readonly property real progress: player && player.length > 0 ? Math.min(1, player.position / player.length) : 0
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property real battery: UPower.displayDevice && UPower.displayDevice.isPresent
                                    ? (UPower.displayDevice.percentage <= 1 ? UPower.displayDevice.percentage : UPower.displayDevice.percentage / 100) : 0
    property date now: new Date()
    property Timer clock: Timer { interval: 1000; running: true; repeat: true; onTriggered: ctx.now = new Date() }
    property PwObjectTracker tracker: PwObjectTracker { objects: [ctx.sink] }

    readonly property var tokens: ["title", "artist", "album", "player", "time", "time24", "date", "day", "battery", "volume"]
    function value(token) {
        switch (token) {
        case "title": return player ? player.trackTitle || "Not Playing" : "Not Playing";
        case "artist": return player ? player.trackArtist || "" : "";
        case "album": return player ? player.trackAlbum || "" : "";
        case "player": return player ? player.identity || "" : "";
        case "time": return Qt.formatTime(now, "h:mm AP");
        case "time24": return Qt.formatTime(now, "HH:mm");
        case "date": return Qt.formatDate(now, "MMMM d");
        case "day": return Qt.formatDate(now, "dddd");
        case "battery": return Math.round(battery * 100) + "%";
        case "volume": return Math.round(volume * 100) + "%";
        }
        return "{" + token + "}";
    }
    function fill(text) {
        // reading these makes bindings that call fill() update when they change
        var _ = [now, player, player ? player.trackTitle : "", player ? player.trackArtist : "", volume, battery];
        return String(text || "").replace(/\{([a-z0-9]+)\}/g, function (m, t) { return ctx.value(t); });
    }
    function progressOf(source) {
        if (source === "battery") return battery;
        if (source === "volume") return volume;
        return progress;
    }

    // ── premade button actions ──
    readonly property var actions: [
        { id: "media.toggle", label: "Play / Pause", icon: "play" },
        { id: "media.next", label: "Next Track", icon: "next" },
        { id: "media.previous", label: "Previous Track", icon: "prev" },
        { id: "media.shuffle", label: "Shuffle", icon: "shuffle" },
        { id: "media.repeat", label: "Repeat", icon: "repeat" },
        { id: "volume.up", label: "Volume Up", icon: "volume" },
        { id: "volume.down", label: "Volume Down", icon: "speaker" },
        { id: "volume.mute", label: "Mute", icon: "speaker" },
        { id: "open.app", label: "Open App…", icon: "folder" },
        { id: "open.url", label: "Open Website…", icon: "link" },
        { id: "open.appstore", label: "App Store", icon: "appstore" },
        { id: "open.settings", label: "System Settings", icon: "gear" },
        { id: "open.spotlight", label: "Spotlight", icon: "search" },
        { id: "open.controlcenter", label: "Control Center", icon: "cc" },
        { id: "none", label: "Nothing", icon: "dots" }
    ]
    function actionInfo(id) {
        for (var i = 0; i < actions.length; i++) if (actions[i].id === id) return actions[i];
        return actions[actions.length - 1];
    }
    // the icon a button shows: Play/Pause follows the player
    function iconFor(item) {
        if (item.icon && item.icon !== "auto") return item.icon;
        if (item.action === "media.toggle") return playing ? "pause" : "play";
        return actionInfo(item.action).icon;
    }
    function run(action, param) {
        var p = player, a = sink && sink.audio ? sink.audio : null;
        switch (action) {
        case "media.toggle": if (p) p.togglePlaying(); break;
        case "media.next": if (p) p.next(); break;
        case "media.previous": if (p) p.previous(); break;
        case "media.shuffle": if (p) { if (p.setShuffle) p.setShuffle(!p.shuffle); else p.shuffle = !p.shuffle; } break;
        case "media.repeat": if (p) { var s = (p.loopState + 1) % 3; if (p.setLoop) p.setLoop(s); else p.loopState = s; } break;
        case "volume.up": if (a) a.volume = Math.min(1, a.volume + 0.05); break;
        case "volume.down": if (a) a.volume = Math.max(0, a.volume - 0.05); break;
        case "volume.mute": if (a) a.muted = !a.muted; break;
        case "open.app": if (param) Quickshell.execDetached(param.match(/(?:[^\s"]+|"[^"]*")+/g).map(function (x) { return x.replace(/^"|"$/g, ""); })); break;
        case "open.url": if (param) Qt.openUrlExternally(/^[a-z]+:/i.test(param) ? param : "https://" + param); break;
        case "open.appstore": if (hub && hub.appStore) hub.appStore.open(""); break;
        case "open.settings": if (hub) hub.openSettings("general"); break;
        case "open.spotlight": if (hub && hub.bar) hub.bar.search(); break;
        case "open.controlcenter": if (hub && hub.bar) hub.bar.ccRequest(true); break;
        }
    }
}
