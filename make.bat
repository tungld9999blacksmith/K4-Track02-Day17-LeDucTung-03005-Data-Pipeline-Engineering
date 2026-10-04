@echo off
REM Lab 17 — Data Pipeline Engineering (Track 2) — Windows Batch Wrapper
REM This batch file wraps the PowerShell script for easy command-line usage

setlocal enabledelayedexpansion

REM Check if PowerShell is available
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: PowerShell not found. Please install Windows PowerShell or use Windows Terminal.
    exit /b 1
)

REM Execute the PowerShell script with all arguments passed through
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make.ps1" %*

endlocal
