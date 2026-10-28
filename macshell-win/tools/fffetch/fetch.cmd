@echo off
rem fetch: FreeForm's system info (FF logo + specs). Works in cmd and PowerShell.
set FFFETCH_SHELL=%FFFETCH_SHELL%
if "%FFFETCH_SHELL%"=="" set FFFETCH_SHELL=cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fetch-core.ps1" %*
set FFFETCH_SHELL=
