@echo off
cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "scripts\main.ps1"
pause