@echo off
rem Solbaram village server launcher (Windows).
rem  1) git pull  2) npm install (only when needed)  3) frees port 8080 if an OLD Solbaram server still holds it  4) npm start
rem Works from the repository root or from the server folder.
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem --- find the server folder (this file may sit in the repo root or in server\) ---
set "SERVER_DIR="
if exist "%~dp0server\package.json" set "SERVER_DIR=%~dp0server"
if not defined SERVER_DIR if exist "%~dp0package.json" set "SERVER_DIR=%~dp0"
if not defined SERVER_DIR (
  echo Cannot find the server folder next to this file. Put server.bat in the claude_connect folder.
  pause
  exit /b 1
)

echo === 1. Update code - git pull ===
git pull
if errorlevel 1 echo [warning] git pull failed - starting with the code you already have.

cd /d "%SERVER_DIR%"

where node >nul 2>nul
if errorlevel 1 goto NONODE

echo.
echo === 2. Packages ===
call npm install --no-audit --no-fund
if errorlevel 1 (
  echo npm install failed. See the message above.
  pause
  exit /b 1
)

rem --- port: stop an old Solbaram server that still holds it, otherwise use the next free port ---
set "PORT=8080"
:CHECKPORT
set "PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:":%PORT% .*LISTENING"') do set "PID=%%p"
if not defined PID goto PORTFREE
set "CMDLINE="
for /f "usebackq delims=" %%c in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter 'ProcessId=%PID%').CommandLine"`) do set "CMDLINE=%%c"
echo !CMDLINE! | findstr /i /c:"src\index.js" /c:"src/index.js" /c:"npm-cli.js" >nul
if not errorlevel 1 (
  echo Port !PORT! is held by an older Solbaram server (PID !PID!^). Stopping it so the updated server can start...
  taskkill /PID !PID! /T /F >nul 2>nul
  timeout /t 2 /nobreak >nul
  goto CHECKPORT
)
echo Port !PORT! is used by another program (PID !PID!^). Trying the next port...
set /a PORT+=1
if !PORT! GTR 8090 (
  echo No free port between 8080 and 8090. Close other programs and try again.
  pause
  exit /b 1
)
goto CHECKPORT

:PORTFREE
echo.
echo === 3. Your PC IP - on the phone use ws://IP:!PORT! ===
echo    (use the 192.168.x.x address on the same Wi-Fi, not 172.x - that one is WSL/Hyper-V)
ipconfig | findstr /i "IPv4"

echo.
echo === 4. Starting server on port !PORT! - close this window to stop ===
call npm start
if errorlevel 2 echo The port was taken while starting. Run this file again.

echo.
echo Server stopped. See the message above.
pause
exit /b

:NONODE
echo Node.js is not installed. Install the LTS version from nodejs.org and run this again.
pause
