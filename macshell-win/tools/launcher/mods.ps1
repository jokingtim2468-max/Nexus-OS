# mods.ps1 — keeps Spotify and Discord themable by FreeForm, run hidden by FreeForm.ps1 at every start.
# Each part runs only when its switch is on (Settings > FreeForm, or the launcher's Configure page):
#   modSpotify  Spicetify (spicetify.app, open source): installed once with winget, then
#               `spicetify upgrade` + `spicetify backup apply` at each start, so it survives Spotify updates.
#               Needs the Spotify installer version (spotify.com), not the Microsoft Store one.
#   modDiscord  Vencord (vencord.dev, open source), via its official VencordInstallerCli.exe: installed once,
#               and installed again when Discord has updated itself (a Discord update removes it).
#               Vencord updates itself after that. Client mods are against Discord's Terms of Service.
# Log: %LOCALAPPDATA%\FreeForm\logs\mods.log
$ErrorActionPreference = 'Continue'
$state = Join-Path $env:LOCALAPPDATA 'FreeForm\mods'
$logDir = Join-Path $env:LOCALAPPDATA 'FreeForm\logs'
New-Item -ItemType Directory -Force -Path $state, $logDir | Out-Null
Start-Transcript -Path (Join-Path $logDir 'mods.log') -Force | Out-Null

$cfg = @{ modSpotify = $true; modDiscord = $true }
$cfgPath = Join-Path $env:APPDATA 'FreeForm\launcher.json'
if (Test-Path $cfgPath) { try { (Get-Content $cfgPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value } } catch {} }

function Refresh-Path { $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' + (Join-Path $env:LOCALAPPDATA 'spicetify') }

# ── Spotify: Spicetify ──
if ($cfg.modSpotify -and (Test-Path (Join-Path $env:APPDATA 'Spotify\Spotify.exe'))) {
    Refresh-Path
    if (-not (Get-Command spicetify -ErrorAction SilentlyContinue)) {
        "Spicetify: installing (winget)"
        winget install --id Spicetify.Spicetify -e --silent --accept-source-agreements --accept-package-agreements | Out-Host
        Refresh-Path
    }
    if (Get-Command spicetify -ErrorAction SilentlyContinue) {
        spicetify upgrade 2>&1 | Out-Host                               # Spicetify's own updater
        # FreeForm's theme folder (theme.py fills its colours when you apply a theme)
        $theme = Join-Path $env:APPDATA 'spicetify\Themes\FreeForm'
        if (-not (Test-Path $theme)) { New-Item -ItemType Directory -Force -Path $theme | Out-Null; '' | Set-Content (Join-Path $theme 'user.css') }
        spicetify -q backup apply 2>&1 | Out-Host                       # re-applies after a Spotify update
        if ($LASTEXITCODE -ne 0) { spicetify -q restore backup apply 2>&1 | Out-Host }
    } else { "Spicetify: not available (winget missing or install failed)" }
} elseif ($cfg.modSpotify) { "Spotify (installer version) not found: Spicetify skipped" }

# ── Discord: Vencord ──
$discord = Join-Path $env:LOCALAPPDATA 'Discord'
if ($cfg.modDiscord -and (Test-Path $discord)) {
    # the newest app-x.y.z folder is the Discord version; a change means Discord updated itself
    $app = Get-ChildItem $discord -Directory -Filter 'app-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    $seenFile = Join-Path $state 'discord-version.txt'
    $seen = if (Test-Path $seenFile) { (Get-Content $seenFile -Raw).Trim() } else { '' }
    $patched = $app -and (Test-Path (Join-Path $app.FullName 'resources\app.asar')) -and (Test-Path (Join-Path $app.FullName 'resources\_app.asar'))
    if ($app -and ($app.Name -ne $seen -or -not $patched)) {
        $cli = Join-Path $state 'VencordInstallerCli.exe'
        "Vencord: installing for $($app.Name)"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe' -OutFile $cli
            & $cli -install -branch auto 2>&1 | Out-Host
            if ($LASTEXITCODE -eq 0) { $app.Name | Set-Content $seenFile }
        } catch { "Vencord: $($_.Exception.Message)" }
    } else { "Vencord: already installed for $($app.Name)" }
} elseif ($cfg.modDiscord) { "Discord not found: Vencord skipped" }

# colours: applying a theme in FreeForm (Settings > Appearance, Theme Studio) writes them into both mods
Stop-Transcript | Out-Null
