# Puts fffetch on your PATH (for your user only, no admin): copies it to %LOCALAPPDATA%\FreeForm\bin.
$dest = Join-Path $env:LOCALAPPDATA 'FreeForm\bin'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'fffetch.ps1'), (Join-Path $PSScriptRoot 'fffetch.cmd') $dest
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($path -split ';') -notcontains $dest) { [Environment]::SetEnvironmentVariable('Path', ($path.TrimEnd(';') + ";$dest"), 'User') }
Write-Host "fffetch installed. Open a new cmd or PowerShell window and type: fffetch"
