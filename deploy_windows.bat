@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_windows.ps1" %*
exit /b %errorlevel%
