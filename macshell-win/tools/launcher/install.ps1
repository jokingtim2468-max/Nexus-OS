# Installs FreeForm for the current user (no admin): Desktop + Start Menu shortcuts, fetch on PATH,
# and optionally start at sign-in.   install.ps1 [-AutoStart] | install.ps1 -Uninstall
param([switch]$AutoStart, [switch]$Uninstall)
$root = $PSScriptRoot
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\FreeForm.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FreeForm.lnk'   # follows OneDrive's Desktop too
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$bin = Join-Path $root 'tools\fffetch'
if ($Uninstall) {
    & (Join-Path $root 'FreeForm.ps1') -Stop
    Remove-Item $startMenu, $desktop -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runKey -Name FreeForm -ErrorAction SilentlyContinue
    $p = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (($p -split ';') | Where-Object { $_ -and $_ -ne $bin }) -join ';', 'User')
    Write-Host 'FreeForm removed (files in this folder are left as they are).'; exit 0
}
$ws = New-Object -ComObject WScript.Shell
# Windows caches shortcut icons by file path: a new name per version makes it pick up a new icon
$ver = 'dev'; $vf = Join-Path $root 'version.txt'; if (Test-Path $vf) { $ver = (Get-Content $vf -Raw).Trim() -replace '[^A-Za-z0-9.-]', '' }
Get-ChildItem $root -Filter 'FreeForm-*.ico' -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
$ico = Join-Path $root "FreeForm-$ver.ico"
Copy-Item (Join-Path $root 'shell\assets\freeform.ico') $ico -Force -ErrorAction SilentlyContinue
foreach ($path in $startMenu, $desktop) {
    $lnk = $ws.CreateShortcut($path)
    $lnk.TargetPath = Join-Path $root 'FreeFormLauncher.cmd'            # the launcher window (Launch / Configure)
    $lnk.WorkingDirectory = $root
    $lnk.WindowStyle = 7                                          # minimized: no console flash
    $lnk.Description = 'FreeForm'
    if (Test-Path $ico) { $lnk.IconLocation = $ico }
    $lnk.Save()
}
& ie4uinit.exe -show 2>$null                                     # refresh Windows' icon cache
# FreeForm's wallpapers go where Settings > Wallpaper looks by default (never overwriting yours)
$walls = Join-Path $env:USERPROFILE 'Pictures\Wallpapers'
New-Item -ItemType Directory -Force -Path $walls | Out-Null
Get-ChildItem (Join-Path $root 'shell\assets\wallpapers') -File | ForEach-Object {
    $dest = Join-Path $walls $_.Name
    if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest }
}
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($p -split ';') -notcontains $bin) { [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ";$bin"), 'User') }
if ($AutoStart) { Set-ItemProperty -Path $runKey -Name FreeForm -Value "`"$(Join-Path $root 'FreeForm.cmd')`"" }
Write-Host 'FreeForm installed: double-click FreeForm on your Desktop (or Start Menu > FreeForm) to open the launcher. Type fetch in a new terminal.'
if ($AutoStart) { Write-Host 'It will start when you sign in.' }
