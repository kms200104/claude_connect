@echo off
rem Solbaram test server (Windows) - no git, no Node.js install needed (node\node.exe is included).
rem Double-click to start. Phones on the same Wi-Fi connect to ws://<this PC's 192.168.x.x>:<port>.
rem Test tools are ON (DEV_TOOLS=1): the app's Settings shows "test: get 200,000,000,000 sol".
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "NODE=%~dp0node\node.exe"
if not exist "%NODE%" (
  echo node\node.exe is missing. Unzip the whole package again.
  pause
  exit /b 1
)
set "DEV_TOOLS=1"
set "SAVE_DIR=%~dp0saves"

rem --- port: stop an old Solbaram server that still holds it, otherwise use the next free port ---
set "PORT=8080"
:CHECKPORT
set "PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:":%PORT% .*LISTENING"') do set "PID=%%p"
if not defined PID goto PORTFREE
set "CMDLINE="
for /f "usebackq delims=" %%c in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter 'ProcessId=%PID%').CommandLine"`) do set "CMDLINE=%%c"
echo !CMDLINE! | findstr /i /c:"src\index.js" /c:"src/index.js" >nul
if not errorlevel 1 (
  echo Port !PORT! is held by an older Solbaram server (PID !PID!^). Stopping it...
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
echo ================================================================
echo  Solbaram test server
echo  On the phone, type this server address (same Wi-Fi):
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
  set "IP=%%a"
  set "IP=!IP: =!"
  echo !IP! | findstr /b "192.168. 10." >nul && echo     ws://!IP!:!PORT!
)
echo  (172.x addresses are WSL/Hyper-V - phones cannot reach them)
echo  If Windows asks about the firewall, click "Allow".
echo  Close this window to stop the server. Saves: %SAVE_DIR%
echo ================================================================
echo.
"%NODE%" "%~dp0server\src\index.js"
if errorlevel 2 echo The port was taken while starting. Run this file again.
echo.
echo Server stopped. See the message above.
pause
