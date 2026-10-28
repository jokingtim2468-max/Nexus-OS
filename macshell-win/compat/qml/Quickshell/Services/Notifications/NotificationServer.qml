import QtQuick
import Quickshell
import Quickshell.Io
// Windows notifications (toasts from any app) mirrored into MacShell via notif.ps1
// (UserNotificationListener). Same API as Quickshell's server for what MacShell uses.
// If Windows refuses access, nothing arrives and Windows keeps showing its own toasts.
QtObject {
    id: server
    property bool keepOnReload: true
    property bool bodySupported: true
    property bool bodyMarkupSupported: false
    property bool bodyHyperlinksSupported: false
    property bool bodyImagesSupported: false
    property bool imageSupported: false
    property bool actionsSupported: false
    property bool actionIconsSupported: false
    property bool persistenceSupported: false
    property bool inlineReplySupported: false
    property var trackedNotifications: QtObject { property var values: [] }
    property string access: ""                    // allowed | denied | unavailable
    signal notification(var notification)

    readonly property string ps1dir: Quickshell.env("FREEFORM_HELPER") || ""
    property Component comp: Component { Notification {} }

    property Process watcher: Process {
        running: server.ps1dir !== ""
        command: ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", server.ps1dir + "/notif.ps1", "watch"]
        stdout: SplitParser {
            onRead: line => {
                var d; try { d = JSON.parse(line); } catch (e) { return; }
                if (d.status) { server.access = d.status; return; }
                var n = server.comp.createObject(server, { appName: d.app || "", summary: d.summary || "", body: d.body || "" });
                server.notification(n);
            }
        }
        // restart after sleep/resume or a crash, but not when access was refused
        onExited: if (server.access === "allowed") restart.start()
    }
    property Timer restart: Timer { interval: 5000; onTriggered: server.watcher.running = true }
}
