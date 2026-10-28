@echo off
rem RETROBOOST launcher: double-click to open the app. Extra arguments are passed on, e.g.  RetroBoost.cmd -Demo
where pwsh >nul 2>nul
if errorlevel 1 (
    echo RetroBoost needs PowerShell 7 ^(pwsh^). Install it with:  winget install Microsoft.PowerShell
    pause
    exit /b 1
)
chcp 65001 >nul
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\retroboost.ps1" %*
