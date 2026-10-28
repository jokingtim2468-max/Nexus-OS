# FreeForm launcher (Windows): starts MacShell on qs.exe from this package and takes over the desktop.
#
#   FreeForm.ps1                 start (hides the Windows taskbar while FreeForm runs)
#   FreeForm.ps1 -KeepTaskbar    start but leave the Windows taskbar alone
#   FreeForm.ps1 -Stop           stop FreeForm and bring the taskbar back
#   FreeForm.ps1 -Restore        just bring the taskbar back (if anything went wrong)
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

if ($Restore) { Set-Taskbar $true; exit 0 }
if ($Stop) {
    Get-Process -Name qs -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" } | Stop-Process -Force
    Set-Taskbar $true
    exit 0
}

$env:HOME = $env:USERPROFILE                                   # MacShell keeps its settings in ~/.config
$env:FREEFORM_HELPER = Join-Path $root 'compat\helper'
$env:QML_IMPORT_PATH = (Join-Path $root 'bin\qml') + ';' + (Join-Path $root 'compat\qml')
$env:QS_ICON_THEME_PATH = Join-Path $root 'icons'
$env:PATH = (Join-Path $root 'python') + ';' + $env:FREEFORM_HELPER + ';' + (Join-Path $root 'tools\fffetch') + ';' + $env:PATH
$qs = Join-Path $root 'bin\qs.exe'
$shell = Join-Path $root 'shell\shell.qml'

$p = Start-Process -FilePath $qs -ArgumentList @('-p', "`"$shell`"") -WindowStyle Hidden -PassThru
if (-not $KeepTaskbar) {
    Start-Sleep -Seconds 3
    if (-not $p.HasExited) { Set-Taskbar $false }
}
# Stay alive (hidden) so the taskbar always comes back, also when FreeForm crashes or is closed.
$p.WaitForExit()
Set-Taskbar $true
