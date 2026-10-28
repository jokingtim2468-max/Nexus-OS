@echo off
rem Starts FreeForm without a console window staying open.
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0FreeForm.ps1" %*
