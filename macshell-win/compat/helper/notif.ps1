# notif.ps1 — Windows notifications for the NotificationServer stand-in
# (compat/qml/Quickshell/Services/Notifications), via UserNotificationListener.
#
#   powershell -NoProfile -File notif.ps1 watch     one JSON line per new notification, forever
#
# Lines: {"status":"allowed"|"denied"|"unavailable"} once, then {"id","app","summary","body"} per toast.
# Windows asks once ("Let FreeForm access your notifications?"); Settings > Privacy > Notifications
# can turn it off again. When access is refused, nothing is mirrored and Windows shows its own.
param([string]$Cmd = 'watch')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8   # é, ñ, ó... reach FreeForm intact
$ErrorActionPreference = 'Stop'
function Out-Line($o) { [Console]::Out.WriteLine(($o | ConvertTo-Json -Compress)); [Console]::Out.Flush() }
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function Await($op, [Type]$t) { $x = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $x.Wait(-1) | Out-Null; $x.Result }
    [void][Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.UI.Notifications.UserNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $listener = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    $access = Await ($listener.RequestAccessAsync()) ([Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus])
} catch {
    Out-Line @{ status = 'unavailable'; error = $_.Exception.Message }
    exit 0
}
if ("$access" -ne 'Allowed') { Out-Line @{ status = 'denied' }; exit 0 }
Out-Line @{ status = 'allowed' }

$listType = [System.Collections.Generic.IReadOnlyList[Windows.UI.Notifications.UserNotification]]
$seen = @{}
$first = $true
while ($true) {
    try {
        $list = Await ($listener.GetNotificationsAsync([Windows.UI.Notifications.NotificationKinds]::Toast)) $listType
        foreach ($n in $list) {
            if ($seen.ContainsKey($n.Id)) { continue }
            $seen[$n.Id] = 1
            if ($first) { continue }                                   # what was already there at start-up
            $texts = @()
            try {
                $b = $n.Notification.Visual.GetBinding([Windows.UI.Notifications.KnownNotificationBindings]::ToastGeneric)
                if ($b) { $texts = @($b.GetTextElements() | ForEach-Object { $_.Text }) }
            } catch {}
            $app = ''
            try { $app = $n.AppInfo.DisplayInfo.DisplayName } catch {}
            Out-Line @{ id = $n.Id; app = $app; summary = ($texts | Select-Object -First 1); body = (($texts | Select-Object -Skip 1) -join "`n") }
        }
        $first = $false
    } catch {}
    Start-Sleep -Milliseconds 1500
}
