param(
    [string]$Bind = '',
    [string]$Subnet = '',
    [string]$Tv = '',
    [int]$Port = 8765
)
$ErrorActionPreference = 'Stop'
if (-not $Bind) { $Bind = Read-Host 'IPv4 deste Windows' }
if (-not $Subnet) { $Subnet = Read-Host 'Sub-rede local em CIDR' }
if (-not $Tv) { $Tv = Read-Host 'IPv4 da TV' }

$python = (Get-Command python -ErrorAction Stop).Source
$pythonExe = (& $python -c 'import sys; print(sys.executable)').Trim()
$pythonw = Join-Path (Split-Path -Parent $pythonExe) 'pythonw.exe'
if (-not (Test-Path -LiteralPath $pythonw)) { throw 'Python sem pythonw.exe; instale o Python para Windows.' }

Push-Location $PSScriptRoot
try {
    $check = 'import ipaddress,sys,server; a=server.local_ipv4(sys.argv[1]); t=server.local_ipv4(sys.argv[3]); n=ipaddress.ip_network(sys.argv[2],strict=True); assert a in n and t in n and 1024<=int(sys.argv[4])<=65535; server.certificate(a)'
    & $pythonExe -c $check $Bind $Subnet $Tv $Port
    if ($LASTEXITCODE -ne 0) { throw 'Confira os endereços, a sub-rede e o certificado local.' }

    $local = Join-Path $PSScriptRoot '.local'
    [IO.Directory]::CreateDirectory($local) | Out-Null
    $configPath = Join-Path $local 'service.json'
    $config = @{ bind = $Bind; subnet = $Subnet; tv = $Tv; port = $Port } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))

    $supervisor = Join-Path $PSScriptRoot 'supervisor.py'
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Controle TV Q80A.lnk'
    $shell = New-Object -ComObject WScript.Shell
    if (Test-Path -LiteralPath $shortcutPath) {
        $existing = $shell.CreateShortcut($shortcutPath)
        if ($existing.TargetPath -ne $pythonw -or $existing.Arguments -notlike "*supervisor.py*") {
            throw 'Já existe um atalho com esse nome que não pertence a este controle.'
        }
    }
    $arguments = '"' + $supervisor + '" --config "' + $configPath + '"'
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $pythonw
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Controle local da TV Q80A'
    $shortcut.Save()
    Start-Process -FilePath $pythonw -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    Write-Host 'Inicialização configurada para esta conta Windows. Use mostrar-pin.cmd para consultar o PIN.'
} finally {
    Pop-Location
}
