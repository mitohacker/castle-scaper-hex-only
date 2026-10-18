@echo off
setlocal
cd /d "%~dp0"
rem The viewer: how many things one click can become, Castle Scaper Realistic against Townscaper -- diagrams, animations and turntables
rem rendered by the game itself (viewer\index.html).
rem   viewer-castle-scaper-realistic.bat            rebuild viewer\data.js from the counted numbers and the renders, serve viewer\ and open it
rem   viewer-castle-scaper-realistic.bat nobuild    skip the rebuild
rem   viewer-castle-scaper-realistic.bat dump       count everything again with the game's rules first (headless Godot, about 4 minutes)
rem   viewer-castle-scaper-realistic.bat render     render every picture again with the game first (hidden Godot window, about 10 minutes)
rem After a change to the rules run dump and then render: the pictures follow the numbers.
rem The port is whatever `python ports.py get castle-scaper-realistic-viewer` prints. Close the server window to stop it.

set "BUILD=1"
set "DUMP="
set "RENDER="
:args
if "%~1"=="" goto run
if /i "%~1"=="nobuild" set "BUILD="
if /i "%~1"=="dump" set "DUMP=1"
if /i "%~1"=="render" set "RENDER=1"
shift
goto args

:run
where python >nul 2>nul
if errorlevel 1 (
  echo Python was not found on PATH.
  pause
  exit /b 1
)

set "ROOT=%cd:\=/%"
if defined DUMP (
  echo === counting every neighbourhood with the game's rules ===
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\cs_run.ps1 -Script res://tools/combo_probe.gd -Seconds 900 -ScriptArgs "-- --json=%ROOT%/viewer/data/combos.json"
  if errorlevel 1 (
    echo The count failed.
    pause
    exit /b 1
  )
)
if defined RENDER (
  echo === rendering the pictures with the game ===
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\render_viewer.ps1
  if errorlevel 1 (
    echo The render failed.
    pause
    exit /b 1
  )
)
if defined BUILD (
  echo === rebuilding viewer\data.js ===
  python tools\build_viewer_data.py
  if errorlevel 1 (
    pause
    exit /b 1
  )
)

rem The port comes from the register (C:\Dev\Prototypes\ports.py), never hard-coded. If the viewer is already running it is reused;
rem otherwise the server starts in its own window and the page opens.
python "C:\Dev\Prototypes\ports.py" run castle-scaper-realistic-viewer --path /index.html --ping /index.html -- python "%cd%\tools\serve_viewer.py" {port} --directory "%cd%\viewer"
if errorlevel 1 pause
