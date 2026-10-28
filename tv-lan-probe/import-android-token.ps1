param([string]$ExpectedTvIp = '')

# Transfers an existing Android debug app's TV token directly from ADB stdout
# into Windows user-scoped DPAPI. No plaintext token file or terminal output.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ExpectedTvIp)) {
    $ExpectedTvIp = Read-Host 'IPv4 da TV já salvo no Android'
}
$adbPath = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adbPath) {
    $adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
}
if (-not (Test-Path -LiteralPath $adbPath)) {
    throw 'ADB não está instalado neste Windows.'
}

$lines = @(& $adbPath devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '\S' })
$authorized = @($lines | Where-Object { $_ -match '\sdevice\s*$' })
if ($authorized.Count -ne 1 -or $lines.Count -ne 1) {
    throw 'Conecte exatamente um Android por USB e autorize a depuração USB na tela dele.'
}

try {
    # The command contains no secret. ADB output stays in process memory only.
    $xmlLines = @(& $adbPath exec-out run-as br.com.wesley.controleq80a cat shared_prefs/tv_remote.xml 2>$null)
    if ($LASTEXITCODE -ne 0 -or $xmlLines.Count -eq 0) {
        throw 'O app instalado não permite leitura via run-as. Use a versão debug já instalada.'
    }
    $xmlText = [string]::Join([Environment]::NewLine, $xmlLines)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stringReader = [IO.StringReader]::new($xmlText)
    $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($xmlReader) }
    finally {
        $xmlReader.Dispose()
        $stringReader.Dispose()
        $xmlText = $null
        $xmlLines = $null
    }
    $ipNode = $document.SelectSingleNode('/map/string[@name="ip"]')
    $tokenNode = $document.SelectSingleNode('/map/string[@name="token"]')
    if ($null -eq $ipNode -or $ipNode.InnerText -ne $ExpectedTvIp) {
        throw 'O IP salvo no Android não coincide com o IP atual da TV.'
    }
    if ($null -eq $tokenNode -or
        [string]::IsNullOrWhiteSpace($tokenNode.InnerText) -or
        $tokenNode.InnerText.Length -gt 1024) {
        throw 'O Android ainda não possui token de pareamento válido.'
    }
    $token = $tokenNode.InnerText
    $localDir = Join-Path $PSScriptRoot '.local'
    if (-not (Test-Path -LiteralPath $localDir)) {
        [IO.Directory]::CreateDirectory($localDir) | Out-Null
    }
    $entropy = [Text.Encoding]::UTF8.GetBytes('ControleQ80A Windows TV probe v1')
    $plain = [Text.Encoding]::UTF8.GetBytes($token)
    try {
        $cipher = [Security.Cryptography.ProtectedData]::Protect(
            $plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes((Join-Path $localDir 'token.dpapi'), $cipher)
        [IO.File]::WriteAllText((Join-Path $localDir 'tv-ip.txt'), $ExpectedTvIp)
    } finally {
        [Array]::Clear($plain, 0, $plain.Length)
        $token = $null
        $document = $null
    }
    Write-Host 'Token transferido localmente e protegido com DPAPI. Nenhum valor foi exibido.'
} catch {
    # Avoid including ADB/XML exception text: it may include the token.
    Write-Error 'Não foi possível importar o token. Confira USB, app debug, IP salvo e pareamento.'
}
