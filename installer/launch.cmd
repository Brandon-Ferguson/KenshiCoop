@echo off
rem Started by KenshiCoop-Setup.exe once it has unpacked into a temp folder.
rem The .exe stub is 32-bit, so prefer the 64-bit PowerShell via Sysnative.
set "PS=%windir%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%windir%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%windir%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Setup.ps1"
