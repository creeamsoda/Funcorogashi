@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_godot_separate_joycons.ps1" %*
if errorlevel 1 (
  echo.
  echo Failed to start Godot. See the error above.
  pause
  exit /b 1
)
