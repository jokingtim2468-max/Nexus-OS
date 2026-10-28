import QtQuick
// One mirrored Windows notification (see NotificationServer.qml).
QtObject {
    property string appName: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property int urgency: 1
    property real expireTimeout: -1
    property bool tracked: false
    property bool resident: false
    property var hints: ({})
    property var actions: []
    property string desktopEntry: ""
    signal closed(int reason)
    function dismiss() { closed(2); }
    function expire() { closed(1); }
}
