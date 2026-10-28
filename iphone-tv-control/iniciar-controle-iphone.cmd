@echo off
cd /d "%~dp0"
pwsh -NoProfile -File "%~dp0start.ps1"
echo.
echo O controle foi encerrado. Pressione uma tecla para fechar esta janela.
pause >nul
