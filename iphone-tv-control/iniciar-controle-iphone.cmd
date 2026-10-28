@echo off
cd /d "%~dp0"
if exist "%~dp0.local\service.json" (
  pwsh -NoProfile -File "%~dp0iniciar-configurado.ps1"
) else (
  pwsh -NoProfile -File "%~dp0start.ps1"
)
echo.
echo Pressione uma tecla para fechar esta janela.
pause >nul
