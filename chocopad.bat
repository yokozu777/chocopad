@echo off
title Chocopad
color 0A

echo.
echo ========================================
echo    Chocopad
echo ========================================
echo.

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [INFO] Running as Administrator
    echo.
    echo [INFO] Starting Chocopad...
    echo.
    chcp 65001 >nul
    start "" powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0choco_software.ps1"
    exit
) else (
    echo [WARNING] Not running as Administrator
    echo [INFO] Requesting Administrator privileges...
    echo.
    powershell.exe -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit
)

