@echo off
cd /d "%~dp0"
git restore .
git pull
pause