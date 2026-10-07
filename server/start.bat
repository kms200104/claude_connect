@echo off
cd /d "%~dp0"

echo === 1. Update code - git pull ===
git pull

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
call npm start

echo.
echo Server stopped. See the message above.
pause
exit /b

:NONODE
echo Node.js is not installed. Install the LTS version from nodejs.org and run this again.
pause