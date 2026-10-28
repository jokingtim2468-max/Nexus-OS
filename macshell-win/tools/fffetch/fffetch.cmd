@echo off
rem fffetch for cmd: runs the PowerShell version (Windows PowerShell 5.1 ships with Windows).
set FFFETCH_SHELL=cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fffetch.ps1" %*
set FFFETCH_SHELL=
