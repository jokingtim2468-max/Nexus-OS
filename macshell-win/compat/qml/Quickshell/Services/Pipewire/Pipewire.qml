pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// PipeWire on Windows: the default speaker and microphone through Core Audio
// (compat/helper/audio.ps1). Setting audio.volume / audio.muted changes the Windows volume;
// nodes lists every active speaker / microphone, and choosing one (preferredDefaultAudio*, or
// setDefault(node)) makes it the Windows default device.
Singleton {
    id: pw
    readonly property string ps1dir: Quickshell.env("FREEFORM_HELPER") || ""
    property bool syncing: false

    component Audio: QtObject {
        id: au
        property string flow: "sink"
        property real volume: 0
        property bool muted: false
        property var volumes: [volume]
        onVolumeChanged: if (!pw.syncing && flow !== "") proc.write(flow + " volume " + volume.toFixed(3) + "\n")
        onMutedChanged: if (!pw.syncing && flow !== "") proc.write(flow + " mute " + (muted ? "1" : "0") + "\n")
    }
    component Node: QtObject {
        property string name: ""
        property string description: ""
        property string nickname: description
        property int type: 0
        property bool isSink: false
        property bool isStream: false
        property bool ready: true
        property var properties: ({})
        property QtObject audio: null
    }

    readonly property Node defaultAudioSink: Node {
        name: "windows-default-output"; description: "Speakers"; type: 1; isSink: true
        audio: Audio { flow: "sink" }
    }
    readonly property Node defaultAudioSource: Node {
        name: "windows-default-input"; description: "Microphone"; type: 2
        audio: Audio { flow: "source" }
    }
    property var preferredDefaultAudioSink: defaultAudioSink
    property var preferredDefaultAudioSource: defaultAudioSource
    onPreferredDefaultAudioSinkChanged: setDefault(preferredDefaultAudioSink)
    onPreferredDefaultAudioSourceChanged: setDefault(preferredDefaultAudioSource)
    function setDefault(n) {
        if (!n || n === defaultAudioSink || n === defaultAudioSource || n.name.indexOf("{") < 0) return;
        proc.write("default " + n.name + "\n");
    }
    readonly property var nodes: QtObject { property var values: [pw.defaultAudioSink, pw.defaultAudioSource] }
    // the other devices (the default ones are defaultAudioSink / defaultAudioSource themselves, so `=== default` works)
    property var others: ({})
    Component { id: nodeComp; Node { audio: Audio { flow: "" } } }
    function syncDevices(list, def, isOut) {
        var main = isOut ? defaultAudioSink : defaultAudioSource, out = [];
        for (var i = 0; i < (list || []).length; i++) {
            var d = list[i];
            if (d.id === def) { main.name = d.id; main.description = d.name; out.push(main); continue; }
            var n = others[d.id];
            if (!n) { n = nodeComp.createObject(pw, { name: d.id, type: isOut ? 1 : 2, isSink: isOut }); others[d.id] = n; }
            n.description = d.name;
            out.push(n);
        }
        if (out.indexOf(main) < 0) out.unshift(main);
        return out;
    }
    readonly property var links: QtObject { property var values: [] }
    readonly property var linkGroups: QtObject { property var values: [] }
    readonly property bool ready: true

    Process {
        id: proc
        running: pw.ps1dir !== ""
        stdinEnabled: true
        command: ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", pw.ps1dir + "/audio.ps1"]
        stdout: SplitParser {
            onRead: line => {
                var d; try { d = JSON.parse(line); } catch (e) { return; }
                pw.syncing = true;
                if (d.outs !== undefined) {
                    var v = pw.syncDevices(d.outs, d.defOut, true).concat(pw.syncDevices(d.ins, d.defIn, false));
                    if (JSON.stringify(v.map(function (n) { return n.name + n.description; })) !== JSON.stringify(pw.nodes.values.map(function (n) { return n.name + n.description; })))
                        pw.nodes.values = v;
                }
                if (d.sink && d.sink.volume >= 0) { pw.defaultAudioSink.audio.volume = d.sink.volume; pw.defaultAudioSink.audio.muted = d.sink.muted; }
                if (d.source && d.source.volume >= 0) { pw.defaultAudioSource.audio.volume = d.source.volume; pw.defaultAudioSource.audio.muted = d.source.muted; }
                pw.syncing = false;
            }
        }
        onExited: again.start()
    }
    Timer { id: again; interval: 3000; onTriggered: proc.running = true }
}
