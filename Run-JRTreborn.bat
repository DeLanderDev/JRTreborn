@echo off
:: JRTreborn - Easy launcher for Windows users
:: Double-click this file and choose "Run as administrator"

title JRTreborn - Junkware Removal Tool Reborn

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  [!] Administrator privileges required.
    echo  [!] Right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: Get the directory of this batch file
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%JRTreborn.ps1"

if not exist "%PS_SCRIPT%" (
    echo.
    echo  [!] JRTreborn.ps1 not found in: %SCRIPT_DIR%
    echo  [!] Please ensure all files are in the same folder.
    echo.
    pause
    exit /b 1
)

echo.
echo  Starting JRTreborn...
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%PS_SCRIPT%"

echo.
echo  JRTreborn has finished. Press any key to close.
pause >nul
