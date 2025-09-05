@echo off
cd /d "%~dp0"
pwsh -ExecutionPolicy Bypass -File "scripts\main.ps1" %*
REM pause