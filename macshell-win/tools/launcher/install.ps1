# Installs FreeForm for the current user (no admin): Start Menu shortcut, fffetch on PATH,
# and optionally start at sign-in.   install.ps1 [-AutoStart] | install.ps1 -Uninstall
param([switch]$AutoStart, [switch]$Uninstall)
$root = $PSScriptRoot
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\FreeForm.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$bin = Join-Path $root 'tools\fffetch'
if ($Uninstall) {
    & (Join-Path $root 'FreeForm.ps1') -Stop
    Remove-Item $startMenu -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runKey -Name FreeForm -ErrorAction SilentlyContinue
    $p = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (($p -split ';') | Where-Object { $_ -and $_ -ne $bin }) -join ';', 'User')
    Write-Host 'FreeForm removed (files in this folder are left as they are).'; exit 0
}
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($startMenu)
$lnk.TargetPath = Join-Path $root 'FreeForm.cmd'
$lnk.WorkingDirectory = $root
$ico = Join-Path $root 'shell\assets\freeform.ico'
if (Test-Path $ico) { $lnk.IconLocation = $ico }
$lnk.Save()
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($p -split ';') -notcontains $bin) { [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ";$bin"), 'User') }
if ($AutoStart) { Set-ItemProperty -Path $runKey -Name FreeForm -Value "`"$(Join-Path $root 'FreeForm.cmd')`"" }
Write-Host 'FreeForm installed: Start Menu > FreeForm. Type fffetch in a new terminal.'
if ($AutoStart) { Write-Host 'It will start when you sign in.' }
