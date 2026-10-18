@echo off
setlocal
cd /d "%~dp0"

set "GODOT="
if defined GODOT_PATH if exist "%GODOT_PATH%" set "GODOT=%GODOT_PATH%"
if not defined GODOT if exist "C:\Dev\Godot\Godot_v4.7.1-stable_win64.exe" set "GODOT=C:\Dev\Godot\Godot_v4.7.1-stable_win64.exe"
if not defined GODOT if exist "C:\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe" set "GODOT=C:\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe"
if not defined GODOT (
  echo Godot 4.7 was not found.
  echo Set GODOT_PATH to Godot_v4.7.1-stable_win64.exe or put it in C:\Dev\Godot
  pause
  exit /b 1
)

echo Launching Castle Scaper Hex from %cd%
echo   Click to put a block, right-click to take one away, pick a colour below.
echo   Towers, roofs, battlements, gates and courtyards come out of what is around each block.
start "Castle Scaper Hex" "%GODOT%" --path "%cd%"
