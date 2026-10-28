# media.ps1 — Windows "now playing" for the Mpris stand-in (compat/qml/Quickshell/Services/Mpris).
# Uses GlobalSystemMediaTransportControlsSessionManager (GSMTC): every app that shows up in the
# Windows media overlay (Spotify, browsers, VLC, Groove, ...) is a player.
#
#   powershell -NoProfile -File media.ps1 watch                  one JSON line per change, forever
#   powershell -NoProfile -File media.ps1 <app id> play|pause|toggle|next|previous|seek <seconds>|shuffle on|off|loop none|track|playlist
#
# watch line: {"players":[{id,identity,title,artist,album,art,playing,position,length,canNext,canPrev,canSeek,shuffle,loop}]}
param([Parameter(Position = 0)][string]$Cmd, [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $x = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $x.Wait(-1) | Out-Null; $x.Result }
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
$T = 'Windows.Media.Control.GlobalSystemMediaTransportControlsSession'
$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

$artDir = Join-Path $env:TEMP 'freeform-media'
New-Item -ItemType Directory -Force -Path $artDir | Out-Null
$artCache = @{}

function Save-Art($s, $p, $key) {
    if ($artCache.ContainsKey($key)) { return $artCache[$key] }
    $path = ''
    try {
        if ($p.Thumbnail) {
            $stream = Await ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
            $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
            $n = [uint32]$stream.Size
            Await ($reader.LoadAsync($n)) ([uint32]) | Out-Null
            $bytes = New-Object byte[] $n; $reader.ReadBytes($bytes)
            $path = Join-Path $artDir ("art-{0}.png" -f ([Math]::Abs($key.GetHashCode())))
            [IO.File]::WriteAllBytes($path, $bytes)
        }
    } catch {}
    # apps often publish the cover a moment after the title: only remember a cover once we have one
    if ($path) { $artCache[$key] = $path }
    $path
}

function Snapshot {
    $out = @()
    foreach ($s in $mgr.GetSessions()) {
        try {
            $p = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
            $pb = $s.GetPlaybackInfo(); $tl = $s.GetTimelineProperties(); $c = $pb.Controls
            $key = "$($s.SourceAppUserModelId)|$($p.Title)|$($p.Artist)"
            $pos = $tl.Position.TotalSeconds
            if ("$($pb.PlaybackStatus)" -eq 'Playing') { $pos += ((Get-Date).ToUniversalTime() - $tl.LastUpdatedTime.UtcDateTime).TotalSeconds }
            $out += [ordered]@{
                id = $s.SourceAppUserModelId; identity = ($s.SourceAppUserModelId -replace '\.exe$', '' -replace '^.*!', '')
                title = $p.Title; artist = $p.Artist; album = $p.AlbumTitle; art = (Save-Art $s $p $key)
                playing = ("$($pb.PlaybackStatus)" -eq 'Playing'); position = [Math]::Round([Math]::Max(0, $pos), 1)
                length = [Math]::Round(($tl.EndTime - $tl.StartTime).TotalSeconds, 1)
                canNext = $c.IsNextEnabled; canPrev = $c.IsPreviousEnabled; canSeek = $c.IsPlaybackPositionEnabled
                shuffle = [bool]$pb.IsShuffleActive; loop = "$($pb.AutoRepeatMode)"
            }
        } catch {}
    }
    @{ players = $out } | ConvertTo-Json -Depth 4 -Compress
}

if ($Cmd -eq 'watch') {
    $last = ''
    while ($true) {
        $j = Snapshot
        # positions tick every second; only print when something else changed or every 5 s for the clock
        $cmp = $j -replace '"position":[0-9.]+', ''
        if ($cmp -ne $last -or ((Get-Date).Second % 5 -eq 0)) { [Console]::Out.WriteLine($j); [Console]::Out.Flush(); $last = $cmp }
        Start-Sleep -Milliseconds 1000
    }
}

$s = $mgr.GetSessions() | Where-Object { $_.SourceAppUserModelId -eq $Cmd } | Select-Object -First 1
if (-not $s) { $s = $mgr.GetCurrentSession() }
if (-not $s) { [Console]::Error.WriteLine('No media is playing.'); exit 2 }
$a = $Rest[0]
switch ($a) {
    'play' { $op = $s.TryPlayAsync() }
    'pause' { $op = $s.TryPauseAsync() }
    'toggle' { $op = $s.TryTogglePlayPauseAsync() }
    'next' { $op = $s.TrySkipNextAsync() }
    'previous' { $op = $s.TrySkipPreviousAsync() }
    'seek' { $op = $s.TryChangePlaybackPositionAsync([long]([double]$Rest[1] * 10000000)) }
    'shuffle' { $op = $s.TryChangeShuffleActiveAsync($Rest[1] -eq 'on') }
    'loop' { $m = @{ none = 0; track = 1; playlist = 2 }[$Rest[1]]; $op = $s.TryChangeAutoRepeatModeAsync($m) }
    default { [Console]::Error.WriteLine("media.ps1: unknown action '$a'"); exit 64 }
}
Await $op ([bool]) | Out-Null
