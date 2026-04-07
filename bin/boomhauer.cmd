@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boomhauer.ps1" %*
exit /b %ERRORLEVEL%
