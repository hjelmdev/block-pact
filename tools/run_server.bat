@echo off
rem Starts the Block Pact dedicated server on this Windows computer.
rem Rooms show up in the game's public room list (also on the web version).
rem
rem Point GODOT at the *console* Godot executable if it isn't on PATH, e.g.
rem   set GODOT=C:\Godot\Godot_v4.7-stable_win64_console.exe
if "%GODOT%"=="" set GODOT=Godot_v4.7-stable_win64_console.exe

rem Highscore verification: put the Supabase service_role key in
rem tools\service_key.local.txt (git-ignored, never share it).
if exist "%~dp0service_key.local.txt" set /p BLOCK_PACT_SERVICE_KEY=<"%~dp0service_key.local.txt"

set NAME=%~1
if "%NAME%"=="" set NAME=%COMPUTERNAME%

echo Starting Block Pact server "%NAME%" ...  (Ctrl+C to stop)
"%GODOT%" --headless --path "%~dp0.." res://server/server_main.tscn -- --name "%NAME%" --min-open 1 --max-rooms 4
if errorlevel 1 (
  echo.
  echo Could not start Godot. Set GODOT to the path of Godot_v4.7-stable_win64_console.exe, e.g.
  echo   set GODOT=C:\Godot\Godot_v4.7-stable_win64_console.exe
  echo and run this file again.
)
pause
