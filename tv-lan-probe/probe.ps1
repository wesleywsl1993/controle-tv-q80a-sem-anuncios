param(
    [string]$TvIp = '',
    [ValidatePattern('^KEY_[A-Z0-9_]+$')][string]$Key,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'TvCertificatePin.cs')

function Assert-PrivateIp([string]$value) {
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($value, [ref]$address) -or
        $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Informe um IPv4 privado literal.'
    }
    $parts = $address.GetAddressBytes()
    if (-not ($parts[0] -eq 10 -or
        ($parts[0] -eq 172 -and $parts[1] -ge 16 -and $parts[1] -le 31) -or
        ($parts[0] -eq 192 -and $parts[1] -eq 168))) {
        throw 'O IP da TV precisa estar em uma rede privada.'
    }
    # Reject alternative spellings accepted by some IP parsers.
    if ($address.ToString() -cne $value) {
        throw 'Use o IPv4 da TV em quatro números decimais.'
    }
}

$entropy = [Text.Encoding]::UTF8.GetBytes('ControleQ80A Windows TV probe v1')
$localDir = Join-Path $PSScriptRoot '.local'
$tokenPath = Join-Path $localDir 'token.dpapi'
$pinPath = Join-Path $localDir 'certificate.sha256'
$ipPath = Join-Path $localDir 'tv-ip.txt'

function Save-Token([string]$value) {
    if ([string]::IsNullOrEmpty($value)) { return }
    $plain = [Text.Encoding]::UTF8.GetBytes($value)
    try {
        $cipher = [Security.Cryptography.ProtectedData]::Protect(
            $plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($tokenPath, $cipher)
    } finally {
        [Array]::Clear($plain, 0, $plain.Length)
    }
}

function Load-Token {
    if (-not (Test-Path -LiteralPath $tokenPath)) { return '' }
    try {
        $plain = [Security.Cryptography.ProtectedData]::Unprotect(
            [IO.File]::ReadAllBytes($tokenPath), $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        try { return [Text.Encoding]::UTF8.GetString($plain) }
        finally { [Array]::Clear($plain, 0, $plain.Length) }
    } catch {
        throw 'Token local não pôde ser lido nesta conta Windows. Nenhum segredo foi exibido.'
    }
}

function New-KeyMessage([string]$keyName) {
    return (@{
        method = 'ms.remote.control'
        params = @{
            Cmd = 'Click'
            DataOfCmd = $keyName
            Option = 'false'
            TypeOfRemote = 'SendRemoteKey'
        }
    } | ConvertTo-Json -Depth 4 -Compress)
}

if ($SelfTest) {
    Assert-PrivateIp '192.168.12.34'
    $message = New-KeyMessage 'KEY_HOME' | ConvertFrom-Json -AsHashtable
    if ($message.params.DataOfCmd -ne 'KEY_HOME' -or
        $message.params.TypeOfRemote -ne 'SendRemoteKey') {
        throw 'Falha na montagem do comando.'
    }
    $testBytes = [Text.Encoding]::UTF8.GetBytes('teste-local')
    $protected = [Security.Cryptography.ProtectedData]::Protect(
        $testBytes, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $restored = [Security.Cryptography.ProtectedData]::Unprotect(
        $protected, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    if ([Text.Encoding]::UTF8.GetString($restored) -ne 'teste-local') {
        throw 'DPAPI falhou.'
    }
    $testSocket = [System.Net.WebSockets.ClientWebSocket]::new()
    $testPin = [TvCertificatePin]::new('')
    $testSocket.Options.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
    $testSocket.Options.RemoteCertificateValidationCallback = $testPin.Validate
    $testSocket.Dispose()
    'Autoteste local: IP, JSON, DPAPI e callback TLS OK. Nenhuma conexão feita.'
    return
}

if ([string]::IsNullOrWhiteSpace($TvIp)) { $TvIp = Read-Host 'IPv4 da TV' }
Assert-PrivateIp $TvIp
if (-not (Test-Path -LiteralPath $localDir)) {
    [IO.Directory]::CreateDirectory($localDir) | Out-Null
}
if (Test-Path -LiteralPath $ipPath) {
    $savedIp = (Get-Content -LiteralPath $ipPath -Raw).Trim()
    if ($savedIp -ne $TvIp) {
        throw 'O IP mudou. Não reutilize token/certificado de outra TV. Apague o pareamento local conscientemente antes de prosseguir.'
    }
}
$savedPin = if (Test-Path -LiteralPath $pinPath) {
    (Get-Content -LiteralPath $pinPath -Raw).Trim()
} else { '' }
$savedToken = Load-Token
$name = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Controle Q80A'))
$query = 'name=' + [Uri]::EscapeDataString($name)
if ($savedToken) { $query += '&token=' + [Uri]::EscapeDataString($savedToken) }
$url = [Uri]::new('wss://' + $TvIp + ':8002/api/v2/channels/samsung.remote.control?' + $query)

$pin = [TvCertificatePin]::new($savedPin)
$socket = [System.Net.WebSockets.ClientWebSocket]::new()
$socket.Options.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
$socket.Options.RemoteCertificateValidationCallback = $pin.Validate
$socket.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(15)
$connectTimeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(8))
try {
    Write-Host "Conectando à TV ${TvIp}:8002. Aceite a autorização na TV, se aparecer."
    try {
        $socket.ConnectAsync($url, $connectTimeout.Token).GetAwaiter().GetResult() | Out-Null
    } catch {
        if ($pin.RejectionReason) { throw $pin.RejectionReason }
        throw 'TV indisponível ou conexão TLS recusada. Confira IP, energia e rede.'
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    $connected = $false
    while (-not $connected -and [DateTime]::UtcNow -lt $deadline) {
        $remaining = $deadline - [DateTime]::UtcNow
        $receiveTimeout = [Threading.CancellationTokenSource]::new($remaining)
        $stream = [IO.MemoryStream]::new()
        try {
            do {
                $buffer = [byte[]]::new(4096)
                $segment = [ArraySegment[byte]]::new($buffer)
                $frame = $socket.ReceiveAsync($segment, $receiveTimeout.Token).GetAwaiter().GetResult()
                if ($frame.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    throw 'A TV fechou a conexão antes da autorização.'
                }
                $stream.Write($buffer, 0, $frame.Count)
                if ($stream.Length -gt 65536) { throw 'Resposta da TV maior que o limite.' }
            } while (-not $frame.EndOfMessage)
            if ($frame.MessageType -ne [System.Net.WebSockets.WebSocketMessageType]::Text) { continue }
            $message = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json -AsHashtable
            switch ($message.event) {
                'ms.channel.connect' {
                    if ($pin.ObservedFingerprint -and -not $savedPin) {
                        [IO.File]::WriteAllText($pinPath, $pin.ObservedFingerprint)
                        Write-Host 'Certificado local da TV fixado para conexões futuras (primeiro uso ainda requer rede confiável).'
                    }
                    [IO.File]::WriteAllText($ipPath, $TvIp)
                    $received = [string]$message.data.token
                    if (-not $received -and $message.data.clients) {
                        foreach ($client in $message.data.clients) {
                            if ($client.attributes.token) {
                                $received = [string]$client.attributes.token
                                break
                            }
                        }
                    }
                    if ($received) {
                        Save-Token $received
                        Write-Host 'Autorizado; token protegido com DPAPI para esta conta Windows.'
                    } else {
                        Write-Host 'Autorizado; a TV não informou token reutilizável.'
                    }
                    $connected = $true
                }
                'ms.channel.unauthorized' {
                    Write-Host 'Autorização pendente na TV.'
                }
                'ms.channel.timeOut' {
                    throw 'Autorização esgotada na TV.'
                }
            }
        } finally {
            $stream.Dispose()
            $receiveTimeout.Dispose()
        }
    }
    if (-not $connected) { throw 'Tempo de autorização esgotado.' }
    if ($Key) {
        $payload = [Text.Encoding]::UTF8.GetBytes((New-KeyMessage $Key))
        $segment = [ArraySegment[byte]]::new($payload)
        $socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
        Write-Host "Comando $Key enviado. Confirme a ação na TV."
    } else {
        Write-Host 'Conexão autorizada. Nenhum comando enviado.'
    }
} catch {
    # Never print raw .NET exceptions here: the upstream URL can contain the Samsung token.
    if ($_.Exception.Message -in @(
        'A TV não apresentou certificado.',
        'Certificado da TV fora do período de validade.',
        'Certificado da TV mudou. A conexão foi recusada.',
        'TV indisponível ou conexão TLS recusada. Confira IP, energia e rede.',
        'A TV fechou a conexão antes da autorização.',
        'Resposta da TV maior que o limite.',
        'Autorização esgotada na TV.',
        'Tempo de autorização esgotado.'
    )) {
        Write-Error $_.Exception.Message
    } else {
        $errorKind = $_.Exception.GetBaseException().GetType().Name
        Write-Error "Falha de conexão ou protocolo ($errorKind). Nenhum token foi exibido."
    }
} finally {
    $connectTimeout.Dispose()
    $socket.Dispose()
}
