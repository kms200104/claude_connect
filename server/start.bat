@echo off
cd /d "%~dp0"

echo === 1. Update code - git pull ===
set "OLD_HEAD="
for /f %%h in ('git rev-parse HEAD 2^>nul') do set "OLD_HEAD=%%h"
git pull
if defined OLD_HEAD git diff --name-only --diff-filter=A %OLD_HEAD% HEAD -- "*.gd" | findstr /r "." >nul && echo [notice] New game scripts arrived. If the Godot editor is open, use Project ^> Reload Current Project before pressing F5.

cd server

where node >nul 2>nul
if errorlevel 1 goto NONODE

if exist node_modules goto SKIPINSTALL
echo === Installing packages - first run only ===
call npm install
:SKIPINSTALL

echo.
echo === 2. Your PC IP - use ws://IP:8080 on the phone ===
ipconfig | findstr /i "IPv4"

echo.
echo === 3. Starting server - close this window to stop ===
rem Test tools for your own PC: the settings app shows "Test: get 200 billion sol". Run "set DEV_TOOLS=0" first to turn them off.
if not defined DEV_TOOLS set "DEV_TOOLS=1"
echo Test tools DEV_TOOLS=%DEV_TOOLS% - settings app: "Test: get 200 billion sol"
call npm start

echo.
echo Server stopped. See the message above.
pause
exit /b

:NONODE
echo Node.js is not installed. Install the LTS version from nodejs.org and run this again.
pause