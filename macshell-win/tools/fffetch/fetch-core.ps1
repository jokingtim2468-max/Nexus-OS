# fetch — FreeForm's fastfetch: the FF logo and this PC's specs.
#   fetch              (cmd or PowerShell, once FreeForm is installed; fffetch works too)
#   fetch -NoLogo       specs only
#   fetch -NoAnim       skip the falling-FF intro
param([switch]$NoLogo, [switch]$NoAnim)
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
# the shell the user typed `fetch` in: the parents of this script's powershell.exe are
# [cmd.exe running fetch.cmd,] then the user's shell (cmd, pwsh or Windows PowerShell)
$chain = @(); $procId = $PID
for ($k = 0; $k -lt 3; $k++) {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$procId"
    $parent = if ($proc) { Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)" }
    if (-not $parent) { break }
    $chain += $parent; $procId = $parent.ProcessId
}
$user = if ($chain.Count -gt 1 -and $chain[0].Name -eq 'cmd.exe') { $chain[1] } elseif ($chain.Count -gt 0) { $chain[0] }
$shellName = switch ($user.Name) {
    'pwsh.exe' { 'PowerShell ' + ((Get-Item $user.ExecutablePath).VersionInfo.ProductVersion -split '[ +]')[0] }
    'powershell.exe' { 'Windows PowerShell ' + $PSVersionTable.PSVersion.ToString(2) }
    default { 'cmd' }
}
function fmtUp($t) { $p = @(); if ($t.Days) { $p += "$($t.Days) days" }; if ($t.Hours) { $p += "$($t.Hours) hours" }; $p += "$($t.Minutes) mins"; $p -join ', ' }

$userLine = "$env:USERNAME@$env:COMPUTERNAME"
$info = @(
    "$B$accent$env:USERNAME${R}@$B$accent$env:COMPUTERNAME$R",
    ('-' * $userLine.Length),
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

# the finished lines (logo + specs side by side)
$n = [Math]::Max($logo.Count, $info.Count)
$lines = @()
for ($i = 0; $i -lt $n; $i++) {
    $l = if ($NoLogo) { '' } elseif ($i -lt $logo.Count) { $logo[$i] } else { '  ' + ' ' * 22 }
    # (PowerShell names ignore case: never call a variable $r, it is the colour reset $R)
    $right = if ($i -lt $info.Count) { $info[$i] } else { '' }
    if ($NoLogo) { $lines += $right } else { $lines += ("{0}${R}   {1}" -f $l.PadRight(24 + ($l.Length - ($l -replace "$e\[[0-9;]*m", '').Length)), $right) }
}
function VisLen([string]$t) { ($t -replace "$e\[[0-9;]*m", '').Length }

# ── intro: little FF logos fall with gravity, tumble and bounce, then pile up behind the text ──
$animate = -not $NoAnim -and -not [Console]::IsOutputRedirected -and $Host.UI.RawUI.WindowSize.Width -ge 60
$pile = @()
if ($animate) {
    $rows = $lines.Count + 2
    $width = [Math]::Min($Host.UI.RawUI.WindowSize.Width - 3, 110)
    Write-Host ("`n" * $rows) -NoNewline
    $top = [Console]::CursorTop - $rows
    [Console]::CursorVisible = $false
    $rnd = New-Object Random
    $palette = @(39, 45, 69, 75, 99, 135, 141)
    $floor = @{}                                   # column -> lowest free row
    $ps = @(for ($k = 0; $k -lt 22; $k++) {
        [pscustomobject]@{ x = [double]$rnd.Next(1, $width - 2); y = -[double]$rnd.Next(0, 14); vx = ($rnd.NextDouble() - 0.5) * 0.9
            vy = 0.0; spin = $rnd.Next(0, 4); c = $palette[$rnd.Next(0, $palette.Count)]; done = $false; ox = -1; oy = -1; bounces = 0 } })
    $glyphs = @('FF', "$([char]0x2132)$([char]0x2132)", 'FF', "$([char]0x2132)F")   # F, turned F: it tumbles
    for ($f = 0; $f -lt 70 -and ($ps | Where-Object { -not $_.done }); $f++) {
        foreach ($p in $ps) {
            if ($p.done) { continue }
            $p.vy += 0.16; $p.y += $p.vy; $p.x += $p.vx
            if ($p.x -lt 0) { $p.x = 0; $p.vx = -$p.vx }
            if ($p.x -gt $width - 2) { $p.x = $width - 2; $p.vx = -$p.vx }
            $col = [int][Math]::Round($p.x)
            $ground = if ($floor.ContainsKey($col)) { $floor[$col] } else { $rows - 1 }
            if ($p.y -ge $ground) {
                $p.y = $ground
                if ($p.bounces -lt 2 -and [Math]::Abs($p.vy) -gt 0.5) { $p.vy = -$p.vy * 0.45; $p.vx *= 0.6; $p.bounces++ }
                else { $p.done = $true; foreach ($dc in -1..2) { $floor[$col + $dc] = $ground - 1 } }
            }
            $px = [int][Math]::Round($p.x); $py = [int][Math]::Floor($p.y)
            if ($p.oy -ge 0 -and ($p.ox -ne $px -or $p.oy -ne $py)) { [Console]::SetCursorPosition($p.ox, $top + $p.oy); [Console]::Write('  ') }
            if ($py -ge 0) {
                $g = if ($p.done) { 'FF' } else { $glyphs[($p.spin + $f) % 4] }
                [Console]::SetCursorPosition($px, $top + $py); [Console]::Write("$(c $p.c)$g$R")
                $p.ox = $px; $p.oy = $py
            }
        }
        Start-Sleep -Milliseconds 28
    }
    $pile = $ps | Where-Object { $_.oy -ge 0 }
    [Console]::SetCursorPosition(0, $top)
}

Write-Host ""
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($animate) { [Console]::SetCursorPosition(0, $top + 1 + $i); [Console]::Write((' ' * (VisLen $lines[$i]))) ; [Console]::SetCursorPosition(0, $top + 1 + $i) }
    Write-Host $lines[$i]
}
if ($animate) {
    # the fallen logos stay where the text doesn't cover them: "behind" it
    foreach ($p in $pile) {
        $row = $p.oy - 1
        $textLen = if ($row -ge 0 -and $row -lt $lines.Count) { VisLen $lines[$row] } else { 0 }
        if ($p.ox -ge $textLen) { [Console]::SetCursorPosition($p.ox, $top + $p.oy); [Console]::Write("$(c $p.c)FF$R") }
    }
    [Console]::SetCursorPosition(0, $top + $rows)
    [Console]::CursorVisible = $true
}
Write-Host ""
