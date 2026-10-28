@echo off
rem Opens the FreeForm launcher window (Launch FreeForm / Configure settings).
start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0FreeFormLauncher.ps1" %*
