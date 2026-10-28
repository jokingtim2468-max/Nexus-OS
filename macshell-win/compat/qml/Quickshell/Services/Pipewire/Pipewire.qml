pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// PipeWire on Windows: the default speaker and microphone through Core Audio
// (compat/helper/audio.ps1). Setting audio.volume / audio.muted changes the Windows volume.
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
        onVolumeChanged: if (!pw.syncing) proc.write(flow + " volume " + volume.toFixed(3) + "\n")
        onMutedChanged: if (!pw.syncing) proc.write(flow + " mute " + (muted ? "1" : "0") + "\n")
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
        name: "windows-default-output"; description: "Speakers"; type: 0; isSink: true
        audio: Audio { flow: "sink" }
    }
    readonly property Node defaultAudioSource: Node {
        name: "windows-default-input"; description: "Microphone"; type: 1
        audio: Audio { flow: "source" }
    }
    property var preferredDefaultAudioSink: defaultAudioSink
    property var preferredDefaultAudioSource: defaultAudioSource
    readonly property var nodes: QtObject { property var values: [pw.defaultAudioSink, pw.defaultAudioSource] }
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
                if (d.sink && d.sink.volume >= 0) { pw.defaultAudioSink.audio.volume = d.sink.volume; pw.defaultAudioSink.audio.muted = d.sink.muted; }
                if (d.source && d.source.volume >= 0) { pw.defaultAudioSource.audio.volume = d.source.volume; pw.defaultAudioSource.audio.muted = d.source.muted; }
                pw.syncing = false;
            }
        }
        onExited: again.start()
    }
    Timer { id: again; interval: 3000; onTriggered: proc.running = true }
}
