@echo off
setlocal
cd /d "%~dp0"

set "GODOT="
if defined GODOT_PATH if exist "%GODOT_PATH%" set "GODOT=%GODOT_PATH%"
if not defined GODOT if exist "C:\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe" set "GODOT=C:\Dev\Godot\Godot_v4.7.1-stable_win64_console.exe"
if not defined GODOT if exist "C:\Dev\Godot\Godot_v4.7.1-stable_win64.exe" set "GODOT=C:\Dev\Godot\Godot_v4.7.1-stable_win64.exe"
if not defined GODOT (
  echo Godot 4.7 was not found.
  pause
  exit /b 1
)
set "GUARD=%~dp0..\.claude\skills\memory-guard\guard_run.ps1"

echo === every script compiles ===
"%GODOT%" --headless --audio-driver Dummy --path "%cd%" --script res://tools/check_scripts.gd
if errorlevel 1 goto failed

echo.
echo === core: the grid, the rules, every starter and random castles audited, the birds ===
"%GODOT%" --headless --audio-driver Dummy --path "%cd%" --script res://tests/verify_cs_core.gd
if errorlevel 1 goto failed

echo.
echo === editor driven with mouse and keys (windowed, under the memory guard) ===
if exist "%GUARD%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%GUARD%" -WorkDir "%cd%" -Seconds 120 -LimitGB 2.5 -TimeIsFailure -ShowLog -Exe "%GODOT%" -ExeArgs "--path . --audio-driver Dummy --resolution 1600x900 --script res://tests/verify_cs_editor.gd -- --cs-fresh"
) else (
  "%GODOT%" --path "%cd%" --audio-driver Dummy --resolution 1600x900 --script res://tests/verify_cs_editor.gd -- --cs-fresh
)
if errorlevel 1 goto failed

echo.
echo === every light at every quality (windowed, under the memory guard; shader errors fail it) ===
if exist "%GUARD%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%GUARD%" -WorkDir "%cd%" -Seconds 240 -LimitGB 3.5 -TimeIsFailure -ShowLog -WindowMode Hidden -Exe "%GODOT%" -ExeArgs "--path . --audio-driver Dummy --resolution 1280x720 --script res://tests/verify_cs_look.gd -- --cs-fresh --cs-starter=castle"
) else (
  "%GODOT%" --path "%cd%" --audio-driver Dummy --resolution 1280x720 --script res://tests/verify_cs_look.gd -- --cs-fresh --cs-starter=castle
)
if errorlevel 1 goto failed
findstr /i /c:"SHADER ERROR" /c:"Parse Error" /c:"SCRIPT ERROR" "%cd%	mp\guard_run.log" "%cd%	mp\guard_run.log.err" >nul 2>nul
if not errorlevel 1 (
  echo A shader or script printed an error during the look run, see tmp\guard_run.log.err
  goto failed
)

echo.
echo All checks passed.
pause
exit /b 0

:failed
echo.
echo A check FAILED (see above).
pause
exit /b 1
