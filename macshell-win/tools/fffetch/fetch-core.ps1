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
# ── look: black & white on a gray card, like a fastfetch preset ──
$BG = "$e[48;5;237m"                 # the card: dark gray
$R = "$e[0m"                         # full reset (only at the end of a line)
$KEY = "$e[1;38;5;255m"              # keys: bold white
$VAL = "$e[22;38;5;250m"             # values: light gray (also ends bold without dropping the card)
$DIM = "$e[22;38;5;244m"             # rules, shading
$W = c 255; $S = c 244               # logo: white strokes, gray shading

# The FF logo drawn with letters, the way distro logos are: white F strokes, gray right/bottom edge
$logo = @(
    "$W FFFFFFFFFF$S:$W  FFFFFFFFFF$S:",
    "$W FFFFFFFFFF$S:$W  FFFFFFFFFF$S:",
    "$W FFF$S:::::::$W   FFF$S:::::::",
    "$W FFF$S:        $W FFF$S:",
    "$W FFFFFFFF$S:   $W FFFFFFFF$S:",
    "$W FFFFFFFF$S:   $W FFFFFFFF$S:",
    "$W FFF$S:::::    $W FFF$S:::::",
    "$W FFF$S:        $W FFF$S:",
    "$W FFF$S:        $W FFF$S:",
    "$W FFF$S:        $W FFF$S:",
    "$S  ::::        ::::",
    "",
    "$W    F R E E F O R M"
)
$logoW = 26

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic Display|Remote' }
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1
$swap = Get-CimInstance Win32_PageFileUsage | Select-Object -First 1
$up = (Get-Date) - $os.LastBootUpTime
$ram = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
$ramT = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$ramP = [Math]::Round($ram / $ramT * 100)
$dU = [Math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2); $dT = [Math]::Round($disk.Size / 1GB, 2)
$dP = [Math]::Round($dU / $dT * 100)
$build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion')
$ver = if ($build.DisplayVersion) { $build.DisplayVersion } else { $build.ReleaseId }
$apps = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' |
        Get-ItemProperty | Where-Object { $_.DisplayName -and -not $_.SystemComponent }).Count
$winget = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and $_.SignatureKind -eq 'Store' }).Count
Add-Type -AssemblyName System.Windows.Forms
$hz = ($gpus | Select-Object -First 1).CurrentRefreshRate
$displays = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)" + $(if ($hz) { " @ $hz Hz" } else { '' }) + $(if ($_.Primary) { ' [Primary]' } else { '' }) })
$dark = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme -eq 0
$ffRunning = [bool](Get-Process -Name qs, quickshell -ErrorAction SilentlyContinue)
$ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127|169\.254)\.' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
$term = if ($env:WT_SESSION) { 'Windows Terminal' } elseif ($env:TERM_PROGRAM) { $env:TERM_PROGRAM } else { 'Windows Console Host' }
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
function fmtUp($t) { $p = @(); if ($t.Days) { $p += "$($t.Days) day$(if ($t.Days -ne 1) {'s'})" }; if ($t.Hours) { $p += "$($t.Hours) hour$(if ($t.Hours -ne 1) {'s'})" }; $p += "$($t.Minutes) min$(if ($t.Minutes -ne 1) {'s'})"; $p -join ', ' }
function kv($k, $v) { "$KEY$k$DIM: $VAL$v" }

# fastfetch's default module order
$userLine = "$env:USERNAME@$env:COMPUTERNAME"
$info = @(
    "$KEY$env:USERNAME$DIM@$KEY$env:COMPUTERNAME",
    "$DIM$('-' * $userLine.Length)",
    (kv 'OS' "$($os.Caption -replace 'Microsoft ', '') $ver $($os.OSArchitecture -replace '-bit', '') bit"),
    (kv 'Host' "$($cs.Manufacturer) $($cs.Model)".Trim()),
    (kv 'Kernel' "WIN32_NT $($os.Version)"),
    (kv 'Uptime' (fmtUp $up)),
    (kv 'Packages' "$apps (programs), $winget (store)"),
    (kv 'Shell' $shellName)
)
foreach ($d in $displays) { $info += (kv 'Display' $d) }
$info += (kv 'DE' $(if ($ffRunning) { 'FreeForm (MacShell)' } else { 'FreeForm (off)' }))
$info += (kv 'WM' 'Desktop Window Manager')
$info += (kv 'Theme' "$(if ($dark) { 'Dark' } else { 'Light' }) (System), Black & White (fetch)")
$info += (kv 'Font' $(if ($ffRunning) { 'Open Runde' } else { 'Segoe UI Variable' }))
$info += (kv 'Terminal' $term)
$info += (kv 'CPU' "$($cpu.Name.Trim()) ($($cpu.NumberOfLogicalProcessors)) @ $([Math]::Round($cpu.MaxClockSpeed / 1000, 2)) GHz")
foreach ($g in $gpus) { $info += (kv 'GPU' "$($g.Name)") }
$info += (kv 'Memory' "$ram GiB / $ramT GiB ($ramP%)")
if ($swap) { $info += (kv 'Swap' "$([Math]::Round($swap.CurrentUsage / 1024, 2)) GiB / $([Math]::Round($swap.AllocatedBaseSize / 1024, 2)) GiB") }
$info += (kv "Disk ($($env:SystemDrive)\)" "$dU GiB / $dT GiB ($dP%) - NTFS")
if ($ip) { $info += (kv "Local IP ($($ip.InterfaceAlias))" "$($ip.IPAddress)/$($ip.PrefixLength)") }
if ($bat) { $info += (kv 'Battery' "$($bat.EstimatedChargeRemaining)%") }
$info += (kv 'Locale' (Get-Culture).Name)
$info += ""
# grayscale "colour" blocks, dark to light
$info += (((232, 234, 236, 238, 240, 242, 244, 246) | ForEach-Object { "$e[48;5;${_}m   " }) -join '') + $BG
$info += (((248, 249, 250, 251, 252, 253, 254, 255) | ForEach-Object { "$e[48;5;${_}m   " }) -join '') + $BG

function VisLen([string]$t) { ($t -replace "$e\[[0-9;]*m", '').Length }

# the finished lines: logo + specs on the gray card, padded so the card is a clean rectangle
$n = [Math]::Max($logo.Count, $info.Count)
$body = @()
for ($i = 0; $i -lt $n; $i++) {
    $l = if ($NoLogo) { '' } elseif ($i -lt $logo.Count) { $logo[$i] } else { '' }
    $l = $l + (' ' * [Math]::Max(0, ($(if ($NoLogo) { 0 } else { $logoW }) - (VisLen $l))))
    # (PowerShell names ignore case: never call a variable $r, it is the reset $R)
    $right = if ($i -lt $info.Count) { $info[$i] } else { '' }
    $body += "  $l$VAL$right"
}
$cardW = ($body | ForEach-Object { VisLen $_ } | Measure-Object -Maximum).Maximum + 3
$blank = ' ' * $cardW
$lines = @("$BG$blank$R") + @($body | ForEach-Object { "$BG$VAL$_" + (' ' * ($cardW - (VisLen $_))) + $R }) + @("$BG$blank$R")

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
    $palette = @(255, 253, 250, 247, 244)
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
        $textLen = if ($row -ge 0 -and $row -lt $lines.Count) { VisLen ($lines[$row] -replace " +($e\[0m)?$", '') } else { 0 }
        if ($p.ox -ge $textLen) {
            $onCard = $row -ge 0 -and $row -lt $lines.Count -and $p.ox + 2 -le $cardW
            [Console]::SetCursorPosition($p.ox, $top + $p.oy); [Console]::Write($(if ($onCard) { $BG } else { '' }) + "$(c $p.c)FF$R")
        }
    }
    [Console]::SetCursorPosition(0, $top + $rows)
    [Console]::CursorVisible = $true
}
Write-Host ""
