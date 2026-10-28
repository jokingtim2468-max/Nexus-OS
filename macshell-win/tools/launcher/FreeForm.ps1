# FreeForm launcher (Windows): starts MacShell on qs.exe from this package and takes over the desktop.
#
#   FreeForm.ps1                 start (hides the Windows taskbar while FreeForm runs)
#   FreeForm.ps1 -KeepTaskbar    start but leave the Windows taskbar and desktop icons alone
#   FreeForm.ps1 -Stop           stop FreeForm and bring the taskbar and desktop icons back
#   FreeForm.ps1 -Restore        just bring the taskbar and desktop icons back (if anything went wrong)
#
# FreeForm only covers Windows visually: the taskbar and desktop icons are hidden (not removed),
# the Windows wallpaper is untouched and everything comes back when FreeForm exits.
#
# Package layout (next to this file):  bin\qs.exe (+ Qt), shell\ (MacShell), compat\, python\, tools\
param([switch]$KeepTaskbar, [switch]$Stop, [switch]$Restore)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Add-Type -Namespace FF -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr FindWindow(string c, string n);
[DllImport("user32.dll")] public static extern System.IntPtr FindWindowEx(System.IntPtr p, System.IntPtr a, string c, string n);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
'@
function Set-Taskbar([bool]$visible) {
    $cmd = if ($visible) { 5 } else { 0 }
    foreach ($cls in 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd') {
        $h = [IntPtr]::Zero
        while (($h = [FF.Win]::FindWindowEx([IntPtr]::Zero, $h, $cls, $null)) -ne [IntPtr]::Zero) { [void][FF.Win]::ShowWindow($h, $cmd) }
    }
}
# Explorer's desktop icon list lives under Progman, or under a WorkerW once a wallpaper slideshow ran
function Set-DesktopIcons([bool]$visible) {
    $cmd = if ($visible) { 5 } else { 0 }
    $hosts = @([FF.Win]::FindWindow('Progman', $null))
    $w = [IntPtr]::Zero
    while (($w = [FF.Win]::FindWindowEx([IntPtr]::Zero, $w, 'WorkerW', $null)) -ne [IntPtr]::Zero) { $hosts += $w }
    foreach ($h in $hosts) {
        $view = [FF.Win]::FindWindowEx($h, [IntPtr]::Zero, 'SHELLDLL_DefView', $null)
        if ($view -ne [IntPtr]::Zero) {
            $list = [FF.Win]::FindWindowEx($view, [IntPtr]::Zero, 'SysListView32', $null)
            if ($list -ne [IntPtr]::Zero) { [void][FF.Win]::ShowWindow($list, $cmd) }
        }
    }
}
function Restore-Windows { Set-Taskbar $true; Set-DesktopIcons $true }

if ($Restore) { Restore-Windows; exit 0 }
if ($Stop) {
    Get-Process -Name qs -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" } | Stop-Process -Force
    Restore-Windows
    exit 0
}

$env:FREEFORM_ROOT = $root
$env:HOME = $env:USERPROFILE                                   # MacShell keeps its settings in ~/.config
$env:FREEFORM_HELPER = Join-Path $root 'compat\helper'
$env:QML_IMPORT_PATH = (Join-Path $root 'bin\qml') + ';' + (Join-Path $root 'compat\qml')
$env:QS_ICON_THEME_PATH = Join-Path $root 'icons'
$env:PATH = (Join-Path $root 'python') + ';' + $env:FREEFORM_HELPER + ';' + (Join-Path $root 'tools\fffetch') + ';' + $env:PATH
$qs = Join-Path $root 'bin\qs.exe'
$shell = Join-Path $root 'shell\shell.qml'

# Start Menu apps -> MacShell's app list (Dock, Spotlight, Launchpad); refreshed in the background
Start-Process -FilePath (Join-Path $env:FREEFORM_HELPER 'macshell-helper.exe') -ArgumentList 'apps', 'sync' -WindowStyle Hidden
# launcher settings (FreeFormLauncher.ps1 > Configure settings)
$hideTaskbar = -not $KeepTaskbar; $hideIcons = -not $KeepTaskbar
$cfgPath = Join-Path $env:APPDATA 'FreeForm\launcher.json'
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($null -ne $cfg.hideTaskbar) { $hideTaskbar = $hideTaskbar -and [bool]$cfg.hideTaskbar }
        if ($null -ne $cfg.hideIcons) { $hideIcons = $hideIcons -and [bool]$cfg.hideIcons }
    } catch {}
}
$p = Start-Process -FilePath $qs -ArgumentList @('-p', "`"$shell`"") -WindowStyle Hidden -PassThru
# Stay alive (hidden) so Windows always comes back, also when FreeForm crashes or is closed.
# While FreeForm runs, re-hide every ~2s: Explorer restarts and new monitors bring the taskbar back.
try {
    Start-Sleep -Seconds 3
    while (-not $p.HasExited) {
        if ($hideTaskbar) { Set-Taskbar $false }
        if ($hideIcons) { Set-DesktopIcons $false }
        [void]$p.WaitForExit(2000)
    }
} finally { Restore-Windows }
