@echo off
title Export Playtest Text Sheets
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server\Export-Playtest.ps1" %*
pause
