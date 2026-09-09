@echo off
rem Double-click to play straight from the source tree using the pinned runtime.
rem For a standalone build you can copy or share, run scripts\package.ps1 instead.
cd /d "%~dp0"
if not exist ".tools\love-11.5-win64\love.exe" (
  echo The pinned LOVE runtime is missing.
  echo Run this first:  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
  echo.
  pause
  exit /b 1
)
if not exist "artifacts" mkdir "artifacts"
start "LoveRTS" ".tools\love-11.5-win64\love.exe" "%~dp0."
