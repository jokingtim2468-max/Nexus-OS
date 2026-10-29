pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// UPower on Windows: the laptop battery from Win32_Battery (compat/helper/power.ps1), read every 30 s.
Singleton {
    id: up
    readonly property string ps1dir: Quickshell.env("FREEFORM_HELPER") || ""
    readonly property QtObject displayDevice: QtObject {
        property bool isPresent: false
        property bool isLaptopBattery: isPresent
        property real percentage: 0          // 0..1, like Quickshell's UPower
        property int state: 0
        property real timeToEmpty: 0
        property real timeToFull: 0
        property bool ready: true
    }
    property bool onBattery: displayDevice.state === 2
    Process {
        id: proc
        command: ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", up.ps1dir + "/power.ps1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d; try { d = JSON.parse(text); } catch (e) { return; }
                up.displayDevice.isPresent = !!d.present;
                up.displayDevice.percentage = (d.percentage || 0) / 100;
                up.displayDevice.state = { Charging: 1, Discharging: 2, FullyCharged: 4 }[d.state] || 0;
            }
        }
    }
    // first reading 6 s after FreeForm starts (helpers starting all at once can fail), then every 30 s
    Timer { interval: 6000; running: up.ps1dir !== ""; onTriggered: proc.running = true }
    Timer { interval: 30000; repeat: true; running: up.ps1dir !== ""; onTriggered: proc.running = true }
}
