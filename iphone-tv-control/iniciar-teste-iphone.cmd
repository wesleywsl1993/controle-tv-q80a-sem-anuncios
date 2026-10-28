@echo off
cd /d "%~dp0"
echo ATENCAO: teste local HTTP sem criptografia entre iPhone e Windows.
echo Use somente na rede domestica confiavel. Ctrl+C encerra.
pwsh -NoProfile -File "%~dp0start.ps1" -HttpTest
echo.
echo O teste foi encerrado. Pressione uma tecla para fechar esta janela.
pause >nul
