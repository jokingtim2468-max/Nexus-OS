import QtQml
// Windows shows its own toasts; reading them (UserNotificationListener) is a later step.
// Same properties as Quickshell's server so MacShell's settings bind; it never receives.
QtObject {
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
    signal notification(var notification)
}
