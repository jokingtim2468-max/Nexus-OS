# One-line FreeForm install for Windows (no admin):
#   irm https://raw.githubusercontent.com/jokingtim2468-max/Nexus-OS/vibe-coded/sharp-noether-i8tg9c/macshell-win/tools/launcher/get.ps1 | iex
# Downloads the latest FreeForm build from GitHub Releases into %LOCALAPPDATA%\FreeForm and runs
# install.ps1 there (Desktop + Start Menu shortcuts, fetch on PATH).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'                          # Invoke-WebRequest is very slow with the bar
$url = 'https://github.com/jokingtim2468-max/Nexus-OS/releases/download/freeform-latest/FreeForm-windows-x64.zip'
$dest = Join-Path $env:LOCALAPPDATA 'FreeForm'
$zip = Join-Path $env:TEMP 'FreeForm-windows-x64.zip'
Write-Host 'Downloading FreeForm...'
try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
catch {
    Write-Host "Couldn't download FreeForm: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host 'If it says Not Found, the first build is still being made; try again in a few minutes.'
    return
}
if (Test-Path (Join-Path $dest 'FreeForm.ps1')) { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'FreeForm.ps1') -Stop }
$tmp = Join-Path $env:TEMP 'FreeForm-unpack'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $zip -DestinationPath $tmp -Force
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $tmp 'FreeForm\*') $dest -Recurse -Force    # updates in place, keeps nothing of yours in here
Remove-Item $tmp, $zip -Recurse -Force -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install.ps1')
# open the launcher window (Launch FreeForm / Configure settings)
Start-Process -FilePath (Join-Path $dest 'FreeFormLauncher.cmd') -WindowStyle Hidden
