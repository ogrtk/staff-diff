@echo off
chcp 65001
cd /d "%~dp0"
pwsh -ExecutionPolicy Bypass -File "scripts\main.ps1" %*
pause