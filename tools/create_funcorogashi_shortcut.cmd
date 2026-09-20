@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0create_funcorogashi_shortcut.ps1"
if errorlevel 1 (
  echo.
  echo Failed to create the project shortcut. See the error above.
  pause
  exit /b 1
)
echo.
echo The funcorogashi Godot shortcut is ready on the desktop.
pause
