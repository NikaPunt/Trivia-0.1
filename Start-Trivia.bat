@echo off
title Antigravity Live Trivia Server
echo ============================================================
echo   ANTIGRAVITY LIVE TRIVIA LAUNCHER
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server\Start-TriviaServer.ps1" %*
pause
