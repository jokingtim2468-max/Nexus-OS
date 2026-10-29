# FreeForm launcher (Windows): starts MacShell on qs.exe from this package and takes over the desktop.
#
#   FreeForm.ps1                 start (hides the Windows taskbar while FreeForm runs)
#   FreeForm.ps1 -KeepTaskbar    start but leave the Windows taskbar and desktop icons alone
#   FreeForm.ps1 -Stop           stop FreeForm and bring the taskbar and desktop icons back
#   FreeForm.ps1 -Restore        just bring the taskbar and desktop icons back (if anything went wrong)
#   FreeForm.ps1 -Force          start even after repeated crashes (the launcher's Launch button)
# "Switch to Windows" in FreeForm only hides it (standby file = 1; the taskbar comes back) and keeps it
# loaded: starting FreeForm again then just wakes the running copy, which is instant.
#
# Crash safety net: if FreeForm crashes it restarts by itself; after 3 crashes within 10 minutes
# it gives up, brings Windows back and says so (state in %APPDATA%\FreeForm\crashes.json).
# Logs: %LOCALAPPDATA%\FreeForm\logs (the last 10 runs).
#
# FreeForm only covers Windows visually: the taskbar and desktop icons are hidden (not removed),
# the Windows wallpaper is untouched and everything comes back when FreeForm exits.
#
# Package layout (next to this file):  bin\qs.exe (+ Qt), shell\ (MacShell), compat\, python\, tools\
param([switch]$KeepTaskbar, [switch]$Stop, [switch]$Restore, [switch]$Force)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
# everything this script does goes to %LOCALAPPDATA%\FreeForm\logs\launcher.log (it runs hidden)
$logDir = Join-Path $env:LOCALAPPDATA 'FreeForm\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
try { Start-Transcript -Path (Join-Path $logDir 'launcher.log') -Append | Out-Null } catch {}

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
# any error: Windows back to normal, and say what went wrong instead of failing silently
trap {
    Write-Output "FAILED: $_"
    try { Restore-Windows } catch {}
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("FreeForm couldn't start:`n`n$_`n`nDetails: $logDir\launcher.log", 'FreeForm', 'OK', 'Error')
    exit 1
}

if ($Restore) { Restore-Windows; exit 0 }
$stateDir = Join-Path $env:APPDATA 'FreeForm'
$stopFlag = Join-Path $stateDir 'stopping'
$crashPath = Join-Path $stateDir 'crashes.json'
if ($Stop) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    Set-Content $stopFlag 'stop'                                 # tells the running launcher this was on purpose
    Remove-Item (Join-Path $stateDir 'standby') -ErrorAction SilentlyContinue
    Get-Process -Name qs -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" } | Stop-Process -Force
    Restore-Windows
    exit 0
}

# Already running (in standby after "Switch to Windows"): wake it instead of starting a second copy
$standbyPath = Join-Path $stateDir 'standby'
if (Get-Process -Name qs -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" }) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    Set-Content $standbyPath '0' -NoNewline
    exit 0
}

$env:FREEFORM_ROOT = $root
$env:HOME = $env:USERPROFILE                                   # MacShell keeps its settings in ~/.config
$env:FREEFORM_HELPER = Join-Path $root 'compat\helper'
$env:QML_IMPORT_PATH = (Join-Path $root 'bin\qml') + ';' + (Join-Path $root 'compat\qml')
$env:QS_ICON_THEME_PATH = Join-Path $root 'icons'
$env:QS_ICON_THEME = 'FreeForm-Mac'                              # macOS-style icons (icons\FreeForm-Mac, from MacTahoe)
$env:PATH = (Join-Path $root 'python') + ';' + $env:FREEFORM_HELPER + ';' + (Join-Path $root 'tools\fffetch') + ';' + $env:PATH
$qs = Join-Path $root 'bin\qs.exe'
$shell = Join-Path $root 'shell\shell.qml'

# Spotify / Discord theming mods (Spicetify, Vencord): installed and kept working in the background (mods.ps1)
Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $root 'mods.ps1')`"") -WindowStyle Hidden
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
# crash history: [timestamps of recent crashes]
function Get-Crashes { try { @((Get-Content $crashPath -Raw | ConvertFrom-Json).crashes) | Where-Object { $_ } } catch { @() } }
function Set-Crashes($list) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null; @{ crashes = @($list) } | ConvertTo-Json | Set-Content $crashPath }
# (PowerShell 5.1 pipes a single $null for an empty list: skip empty entries before reading dates)
function Recent($list) { @($list | Where-Object { $_ -and ([datetime]$_) -gt (Get-Date).AddMinutes(-10) }) }
if ($Force) { Set-Crashes @() }
if ((Recent (Get-Crashes)).Count -ge 3) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("FreeForm crashed 3 times in the last 10 minutes, so it was not started.`n`nOpen the FreeForm launcher and press Launch FreeForm to try again, or Save diagnostics to see what went wrong.", 'FreeForm', 'OK', 'Warning')
    exit 1
}
Get-ChildItem $logDir -Filter 'run-*' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 | Remove-Item -ErrorAction SilentlyContinue
Remove-Item $stopFlag -ErrorAction SilentlyContinue

# Stay alive (hidden) so Windows always comes back, also when FreeForm crashes or is closed.
# While FreeForm runs, re-hide every ~2s: Explorer restarts and new monitors bring the taskbar back.
try {
    while ($true) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $p = Start-Process -FilePath $qs -ArgumentList @('-p', "`"$shell`"") -WindowStyle Hidden -PassThru `
               -RedirectStandardOutput (Join-Path $logDir "run-$stamp.out.log") -RedirectStandardError (Join-Path $logDir "run-$stamp.err.log")
        $null = $p.Handle                                          # (without this, ExitCode stays empty)
        Start-Sleep -Seconds 3
        while (-not $p.HasExited) {
            # Win+Alt+T in FreeForm writes "peek-taskbar": the real taskbar (tray icons) shows for 15 s
            $peek = Get-Item (Join-Path $stateDir 'peek-taskbar') -ErrorAction SilentlyContinue
            $asleep = (Get-Content $standbyPath -Raw -ErrorAction SilentlyContinue) -match '1'
            if ($asleep) { Restore-Windows }                       # switched to Windows: FreeForm hidden, Windows as normal
            else {
                if ($peek -and ((Get-Date) - $peek.LastWriteTime).TotalSeconds -lt 15) { Set-Taskbar $true }
                elseif ($hideTaskbar) { Set-Taskbar $false }
                if ($hideIcons) { Set-DesktopIcons $false }
            }
            [void]$p.WaitForExit(2000)
        }
        $p.WaitForExit()
        # Quit FreeForm / Log Out = exit code 0; FreeForm.ps1 -Stop leaves the flag. Anything else is a crash.
        if ($p.ExitCode -eq 0 -or (Test-Path $stopFlag)) { break }
        $crashes = @(Recent (Get-Crashes)) + @((Get-Date).ToString('o'))
        Set-Crashes $crashes
        if ($crashes.Count -ge 3) {
            Restore-Windows
            Add-Type -AssemblyName PresentationFramework
            [void][System.Windows.MessageBox]::Show("FreeForm stopped after crashing 3 times, and Windows is back to normal.`n`nIn the FreeForm launcher, Save diagnostics collects the logs (they are in $logDir).", 'FreeForm', 'OK', 'Warning')
            break
        }
        Start-Sleep -Seconds 2                                     # crashed: start it again
    }
} finally { Restore-Windows; Remove-Item $stopFlag -ErrorAction SilentlyContinue }
