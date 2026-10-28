$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot '.local\service.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Configure primeiro a inicialização do controle.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$python = (Get-Command python -ErrorAction Stop).Source
$pythonExe = (& $python -c 'import sys; print(sys.executable)').Trim()
$pythonw = Join-Path (Split-Path -Parent $pythonExe) 'pythonw.exe'
if (-not (Test-Path -LiteralPath $pythonw)) { throw 'Python sem pythonw.exe.' }
$supervisor = Join-Path $PSScriptRoot 'supervisor.py'
$arguments = '"' + $supervisor + '" --config "' + $configPath + '"'
Start-Process -FilePath $pythonw -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
Write-Host ("Controle local: https://{0}:{1}/" -f $config.bind, $config.port)
Write-Host 'Se o iPhone pedir um PIN, abra mostrar-pin.cmd neste computador.'
