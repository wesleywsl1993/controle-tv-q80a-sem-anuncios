@echo off
cd /d "%~dp0"
echo PIN temporario do controle:
pwsh -NoProfile -File "%~dp0pair-pin.ps1" -Action Show
echo.
pause
