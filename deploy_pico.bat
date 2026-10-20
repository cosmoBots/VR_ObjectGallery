@echo off
setlocal
if exist "%~dp0android.env.bat" call "%~dp0android.env.bat"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_android.ps1" -Target Pico %*
exit /b %errorlevel%
