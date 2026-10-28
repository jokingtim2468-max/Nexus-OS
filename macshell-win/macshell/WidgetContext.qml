// WidgetContext — live data and premade actions for custom widgets (Widget Studio).
//
// Data a widget's text can show with {tokens}: {title} {artist} {album} {player} {time} {time24}
// {date} {day} {battery} {volume} {cpu} {ram} {ramused} {gpu}.
// System load comes from compat/helper (sysstat.ps1 / sysstat.py), started only once a widget uses it.
// Weather (the "weather" block): MET Norway's forecast (api.met.no) for a city found with
// OpenStreetMap Nominatim — both free, keyless and fine for commercial use with credit. Actions a button can run: see `actions` below. Works on Linux
// (MPRIS / PipeWire / UPower) and on Windows (the stand-ins in compat/qml).
import QtQuick
import Quickshell
import Quickshell.Io
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

    // ── system load (only while a widget shows it) ──
    property bool statsWanted: false
    property var stats: ({ cpu: 0, ram: 0, ramUsed: 0, ramTotal: 0, gpu: 0 })
    property Process statsProc: Process {
        running: ctx.statsWanted
        command: Qt.platform.os === "windows"
            ? ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", (Quickshell.env("FREEFORM_HELPER") || ".") + "/sysstat.ps1"]
            : ["macshell-helper", "stats", "watch"]
        stdout: SplitParser { onRead: line => { try { ctx.stats = JSON.parse(line); } catch (e) {} } }
        onExited: if (ctx.statsWanted) statsRestart.start()
    }
    property Timer statsRestart: Timer { interval: 5000; onTriggered: ctx.statsProc.running = ctx.statsWanted }

    // ── weather per city: { state: loading|ok|error, temp, high, low, symbol, text, place } ──
    property var weather: ({})
    property var weatherAt: ({})                                        // city -> last fetch (ms)
    property Timer weatherTick: Timer { interval: 30 * 60 * 1000; running: true; repeat: true; onTriggered: { for (var c in ctx.weather) ctx.fetchWeather(c, true); } }
    function weatherFor(city) {
        city = String(city || "").trim();
        if (!city) return { state: "error", text: "Set a city" };
        if (!weather[city]) Qt.callLater(fetchWeather, city, false);     // not inside the binding that asked
        return weather[city] || { state: "loading" };
    }
    function setWeather(city, v) { var w = {}; for (var k in weather) w[k] = weather[k]; w[city] = v; weather = w; }
    function getJson(url, cb) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return;
            var d = null;
            if (x.status === 200) { try { d = JSON.parse(x.responseText); } catch (e) {} }
            cb(d);
        };
        x.open("GET", url);
        x.setRequestHeader("User-Agent", "FreeForm-Widgets/1.0 github.com/jokingtim2468-max/Nexus-OS");
        x.send();
    }
    function fetchWeather(city, refresh) {
        var now = Date.now();
        if (!refresh && weatherAt[city] && now - weatherAt[city] < 60000) return;
        var at = {}; for (var k in weatherAt) at[k] = weatherAt[k]; at[city] = now; weatherAt = at;
        if (!weather[city]) setWeather(city, { state: "loading" });
        var old = weather[city];
        var place = old && old.lat !== undefined ? old : null;
        var forecast = function (lat, lon, name) {
            getJson("https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + lat.toFixed(3) + "&lon=" + lon.toFixed(3), function (d) {
                if (!d || !d.properties) { setWeather(city, { state: "error", text: "Weather unavailable", lat: lat, lon: lon, place: name }); return; }
                var ts = d.properties.timeseries || [], cur = ts[0] || {}, inst = (cur.data || {}).instant || {};
                var next = (cur.data || {}).next_1_hours || (cur.data || {}).next_6_hours || {};
                var hi = -999, lo = 999, today = (cur.time || "").substring(0, 10);
                for (var i = 0; i < ts.length && i < 30; i++) {
                    if ((ts[i].time || "").substring(0, 10) !== today) continue;
                    var t = ((ts[i].data || {}).instant || {}).details || {};
                    if (t.air_temperature !== undefined) { hi = Math.max(hi, t.air_temperature); lo = Math.min(lo, t.air_temperature); }
                }
                var sym = ((next.summary || {}).symbol_code || "cloudy");
                setWeather(city, { state: "ok", lat: lat, lon: lon, place: name,
                                   temp: Math.round((inst.details || {}).air_temperature || 0),
                                   high: hi > -999 ? Math.round(hi) : null, low: lo < 999 ? Math.round(lo) : null,
                                   symbol: sym, text: ctx.weatherText(sym) });
            });
        };
        if (place) { forecast(place.lat, place.lon, place.place); return; }
        getJson("https://nominatim.openstreetmap.org/search?format=json&limit=1&q=" + encodeURIComponent(city), function (r) {
            if (!r || !r.length) { setWeather(city, { state: "error", text: "City not found" }); return; }
            forecast(Number(r[0].lat), Number(r[0].lon), String(r[0].display_name || city).split(",")[0]);
        });
    }
    function weatherText(sym) {
        var s = String(sym).replace(/_(day|night|polartwilight)$/, "");
        var map = { clearsky: "Clear", fair: "Mostly Clear", partlycloudy: "Partly Cloudy", cloudy: "Cloudy", fog: "Fog" };
        if (map[s]) return map[s];
        if (/thunder/.test(s)) return "Thunderstorms";
        if (/snow/.test(s)) return "Snow";
        if (/sleet/.test(s)) return "Sleet";
        if (/rain/.test(s)) return /light/.test(s) ? "Light Rain" : /heavy/.test(s) ? "Heavy Rain" : "Rain";
        return "Cloudy";
    }
    function weatherGlyph(sym) {
        var s = String(sym || "");
        if (/thunder/.test(s)) return "\u26C8";
        if (/snow|sleet/.test(s)) return "\u2744";
        if (/rain/.test(s)) return "\u2614";
        if (/fog/.test(s)) return "\u2601";
        if (/clearsky|fair/.test(s)) return /night/.test(s) ? "\u263E" : "\u2600";
        if (/partly/.test(s)) return "\u26C5";
        return "\u2601";
    }

    readonly property var tokens: ["title", "artist", "album", "player", "elapsed", "duration", "remaining", "time", "time24", "date", "day", "battery", "volume", "cpu", "ram", "ramused", "gpu"]
    function mmss(sec) { sec = Math.max(0, Math.floor(sec || 0)); var m = Math.floor(sec / 60), s = sec % 60; return m + ":" + (s < 10 ? "0" : "") + s; }
    function value(token) {
        switch (token) {
        case "title": return player ? player.trackTitle || "Not Playing" : "Not Playing";
        case "artist": return player ? player.trackArtist || "" : "";
        case "album": return player ? player.trackAlbum || "" : "";
        case "player": return player ? player.identity || "" : "";
        case "elapsed": return player ? mmss(player.position) : "0:00";
        case "duration": return player ? mmss(player.length) : "0:00";
        case "remaining": return player ? "-" + mmss(player.length - player.position) : "-0:00";
        case "time": return Qt.formatTime(now, "h:mm AP");
        case "time24": return Qt.formatTime(now, "HH:mm");
        case "date": return Qt.formatDate(now, "MMMM d");
        case "day": return Qt.formatDate(now, "dddd");
        case "battery": return Math.round(battery * 100) + "%";
        case "volume": return Math.round(volume * 100) + "%";
        case "cpu": statsWanted = true; return stats.cpu + "%";
        case "ram": statsWanted = true; return stats.ram + "%";
        case "ramused": statsWanted = true; return stats.ramUsed + " / " + stats.ramTotal + " GB";
        case "gpu": statsWanted = true; return stats.gpu + "%";
        }
        return "{" + token + "}";
    }
    function fill(text) {
        // reading these makes bindings that call fill() update when they change
        var _ = [now, player, player ? player.trackTitle : "", player ? player.trackArtist : "", player ? player.position : 0, volume, battery, stats];
        return String(text || "").replace(/\{([a-z0-9]+)\}/g, function (m, t) { return ctx.value(t); });
    }
    function progressOf(source) {
        if (source === "battery") return battery;
        if (source === "volume") return volume;
        if (source === "cpu" || source === "ram" || source === "gpu") { statsWanted = true; return (stats[source] || 0) / 100; }
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
