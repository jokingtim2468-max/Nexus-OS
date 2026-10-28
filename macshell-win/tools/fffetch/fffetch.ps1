# fffetch — FreeForm's fastfetch: the FF logo and this PC's specs.
#   fffetch            (cmd or PowerShell, once install.ps1 has put it on PATH)
#   fffetch -NoLogo    specs only
param([switch]$NoLogo)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
# colours: Windows PowerShell 5.1 in a cmd window needs virtual-terminal mode switched on
if ($IsWindows -ne $false -and $PSVersionTable.PSVersion.Major -le 5) {
    Add-Type -Namespace FF -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr h, out int m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr h, int m);
'@
    $h = [FF.Con]::GetStdHandle(-11); $m = 0
    if ([FF.Con]::GetConsoleMode($h, [ref]$m)) { [void][FF.Con]::SetConsoleMode($h, $m -bor 4) }
}
$e = [char]27
function c($n) { "$e[38;5;${n}m" }
$R = "$e[0m"; $B = "$e[1m"
# FreeForm blue -> purple, like the logo
$c1 = c 39; $c2 = c 69; $c3 = c 99; $c4 = c 135; $accent = c 75

$logo = @(
    "$c1  ██████████  ██████████",
    "$c1  ██████████  ██████████",
    "$c2  ████        ████      ",
    "$c2  ████        ████      ",
    "$c2  ████████    ████████  ",
    "$c3  ████████    ████████  ",
    "$c3  ████        ████      ",
    "$c4  ████        ████      ",
    "$c4  ████        ████      ",
    "$c4  ████        ████      ",
    "",
    "$c2     F R E E F O R M    "
)

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic Display|Remote' }
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1
$up = (Get-Date) - $os.LastBootUpTime
$ram = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
$ramT = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$ramP = [Math]::Round($ram / $ramT * 100)
$dU = [Math]::Round(($disk.Size - $disk.FreeSpace) / 1GB); $dT = [Math]::Round($disk.Size / 1GB)
$build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion')
$ver = if ($build.DisplayVersion) { $build.DisplayVersion } else { $build.ReleaseId }
$apps = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' |
        Get-ItemProperty | Where-Object { $_.DisplayName -and -not $_.SystemComponent }).Count
Add-Type -AssemblyName System.Windows.Forms
$scr = ([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)" }) -join ', '
$dark = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme -eq 0
$ff = if (Get-Process -Name qs, quickshell -ErrorAction SilentlyContinue) { 'FreeForm (MacShell, running)' } else { 'FreeForm (not running)' }
$shellName = if ($env:PSModulePath -and $Host.Name -match 'ConsoleHost') { "PowerShell $($PSVersionTable.PSVersion)" } else { 'cmd' }
if ($env:FFFETCH_SHELL) { $shellName = $env:FFFETCH_SHELL }
function fmtUp($t) { $p = @(); if ($t.Days) { $p += "$($t.Days) days" }; if ($t.Hours) { $p += "$($t.Hours) hours" }; $p += "$($t.Minutes) mins"; $p -join ', ' }

$user = "$env:USERNAME@$env:COMPUTERNAME"
$info = @(
    "$B$accent$env:USERNAME${R}@$B$accent$env:COMPUTERNAME$R",
    ('-' * $user.Length),
    "$B${accent}OS${R}: $($os.Caption -replace 'Microsoft ', '') $ver ($($os.OSArchitecture))",
    "$B${accent}Host${R}: $($cs.Manufacturer) $($cs.Model)",
    "$B${accent}Kernel${R}: NT $($os.Version)",
    "$B${accent}Uptime${R}: $(fmtUp $up)",
    "$B${accent}Apps${R}: $apps (installed)",
    "$B${accent}Shell${R}: $shellName",
    "$B${accent}Display${R}: $scr",
    "$B${accent}Desktop${R}: $ff",
    "$B${accent}Theme${R}: $(if ($dark) { 'Dark' } else { 'Light' })",
    "$B${accent}CPU${R}: $($cpu.Name.Trim()) ($($cpu.NumberOfLogicalProcessors) threads)"
)
foreach ($g in $gpus) { $info += "$B${accent}GPU${R}: $($g.Name)" }
$info += "$B${accent}Memory${R}: $ram GiB / $ramT GiB ($ramP%)"
$info += "$B${accent}Disk ($($env:SystemDrive))${R}: $dU GB / $dT GB"
if ($bat) { $info += "$B${accent}Battery${R}: $($bat.EstimatedChargeRemaining)%" }
$info += "$B${accent}Locale${R}: $((Get-Culture).Name)"
$info += ""
$info += ((0..7 | ForEach-Object { "$e[4${_}m   " }) -join '') + $R
$info += ((0..7 | ForEach-Object { "$e[10${_}m   " }) -join '') + $R

Write-Host ""
$n = [Math]::Max($logo.Count, $info.Count)
for ($i = 0; $i -lt $n; $i++) {
    $l = if ($NoLogo) { '' } elseif ($i -lt $logo.Count) { $logo[$i] } else { '  ' + ' ' * 22 }
    $r = if ($i -lt $info.Count) { $info[$i] } else { '' }
    if ($NoLogo) { Write-Host $r } else { Write-Host ("{0}$R   {1}" -f $l.PadRight(24 + ($l.Length - ($l -replace "$e\[[0-9;]*m", '').Length)), $r) }
}
Write-Host ""
