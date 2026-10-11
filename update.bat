@echo off
cd /d "%~dp0"
git restore .
set "OLD_HEAD="
for /f %%h in ('git rev-parse HEAD 2^>nul') do set "OLD_HEAD=%%h"
git pull
if defined OLD_HEAD git diff --name-only --diff-filter=A %OLD_HEAD% HEAD -- "*.gd" | findstr /r "." >nul && echo [notice] New game scripts arrived. If the Godot editor is open, use Project ^> Reload Current Project before pressing F5.
pause