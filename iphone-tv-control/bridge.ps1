param([string]$TvIp = '')

# Private line protocol for server.py. Never write a Samsung token or URL to stdout/stderr.
$ErrorActionPreference = 'Stop'
$probeDir = Join-Path $PSScriptRoot '..\tv-lan-probe'
Add-Type -Path (Join-Path $probeDir 'TvCertificatePin.cs')
$localDir = Join-Path $probeDir '.local'
$savedIp = (Get-Content -LiteralPath (Join-Path $localDir 'tv-ip.txt') -Raw).Trim()
if ($TvIp -ne $savedIp -or $TvIp -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') {
    throw 'IP da TV não coincide com o pareamento local.'
}
$fingerprint = (Get-Content -LiteralPath (Join-Path $localDir 'certificate.sha256') -Raw).Trim()
if ($fingerprint -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Certificado da TV não fixado.' }
$entropy = [Text.Encoding]::UTF8.GetBytes('ControleQ80A Windows TV probe v1')
$plain = [Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes((Join-Path $localDir 'token.dpapi')), $entropy,
    [Security.Cryptography.DataProtectionScope]::CurrentUser)
try { $token = [Text.Encoding]::UTF8.GetString($plain) }
finally { [Array]::Clear($plain, 0, $plain.Length) }
if ([string]::IsNullOrWhiteSpace($token)) { throw 'Token da TV ausente.' }
$name = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Controle Q80A'))
$url = [Uri]::new('wss://' + $TvIp + ':8002/api/v2/channels/samsung.remote.control?name=' +
    [Uri]::EscapeDataString($name) + '&token=' + [Uri]::EscapeDataString($token))
$token = $null
$socket = $null

function Close-TvSocket {
    if ($script:socket) { $script:socket.Dispose(); $script:socket = $null }
}

function Connect-Tv {
    if ($script:socket -and $script:socket.State -eq [Net.WebSockets.WebSocketState]::Open) { return }
    Close-TvSocket
    $pin = [TvCertificatePin]::new($fingerprint)
    $script:socket = [Net.WebSockets.ClientWebSocket]::new()
    $script:socket.Options.Proxy = [Net.GlobalProxySelection]::GetEmptyWebProxy()
    $script:socket.Options.RemoteCertificateValidationCallback = $pin.Validate
    $script:socket.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(15)
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(8))
    try {
        $script:socket.ConnectAsync($url, $timeout.Token).GetAwaiter().GetResult() | Out-Null
        $buffer = [byte[]]::new(65536)
        $reply = [IO.MemoryStream]::new()
        try {
            do {
                $part = $script:socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $timeout.Token).GetAwaiter().GetResult()
                if ($part.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw 'TV fechou conexão.' }
                $reply.Write($buffer, 0, $part.Count)
                if ($reply.Length -gt 65536) { throw 'Resposta longa.' }
            } while (-not $part.EndOfMessage)
            $event = [Text.Encoding]::UTF8.GetString($reply.ToArray()) | ConvertFrom-Json -AsHashtable
            if ($event.event -ne 'ms.channel.connect') { throw 'TV não autorizou.' }
        } finally { $reply.Dispose() }
    } catch {
        Close-TvSocket
        throw 'TV indisponível ou conexão não autorizada.'
    } finally { $timeout.Dispose() }
}

function Send-Payload([hashtable]$payload) {
    Connect-Tv
    $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 5 -Compress))
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(5))
    try {
        $script:socket.SendAsync([ArraySegment[byte]]::new($bytes),
            [Net.WebSockets.WebSocketMessageType]::Text, $true, $timeout.Token).GetAwaiter().GetResult() | Out-Null
    } finally { $timeout.Dispose() }
}

function Reply([bool]$ok, [string]$message) {
    [Console]::Out.WriteLine((@{ ok = $ok; message = $message } | ConvertTo-Json -Compress))
    [Console]::Out.Flush()
}

Reply $true 'ready'
try {
    while ($null -ne ($line = [Console]::ReadLine())) {
        try {
            if ($line.Length -gt 4096) { throw 'Pedido longo.' }
            $request = $line | ConvertFrom-Json -AsHashtable
            switch ($request.type) {
                'status' { Connect-Tv; Reply $true 'TV conectada' }
                'key' {
                    $allowed = @('KEY_UP','KEY_DOWN','KEY_LEFT','KEY_RIGHT','KEY_ENTER',
                        'KEY_RETURN','KEY_HOME','KEY_MENU','KEY_VOLUP','KEY_VOLDOWN',
                        'KEY_MUTE','KEY_CHUP','KEY_CHDOWN','KEY_PLAY','KEY_PAUSE',
                        'KEY_STOP','KEY_REWIND','KEY_FF','KEY_POWER')
                    if ($request.key -cnotin $allowed) { throw 'Tecla inválida.' }
                    $count = [int]$request.count
                    if ($count -lt 1 -or $count -gt 8) { throw 'Quantidade inválida.' }
                    for ($i = 0; $i -lt $count; $i++) {
                        Send-Payload @{ method='ms.remote.control'; params=@{
                            Cmd='Click'; DataOfCmd=$request.key; Option='false'; TypeOfRemote='SendRemoteKey' } }
                        if ($i -lt $count - 1) { Start-Sleep -Milliseconds 130 }
                    }
                    Reply $true 'Comando enviado'
                }
                'text' {
                    $value = [string]$request.value
                    if ($value.Length -lt 1 -or $value.Length -gt 200) { throw 'Texto inválido.' }
                    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))
                    Send-Payload @{ method='ms.remote.control'; params=@{
                        Cmd=$encoded; DataOfCmd='base64'; TypeOfRemote='SendInputString' } }
                    Reply $true 'Texto enviado'
                }
                'app' {
                    $appId = [string]$request.id
                    if ($appId -cnotmatch '^[A-Za-z0-9._-]{1,80}$') { throw 'ID inválido.' }
                    Connect-Tv
                    $handler = [Net.Http.HttpClientHandler]::new()
                    $handler.UseProxy = $false
                    $client = [Net.Http.HttpClient]::new($handler)
                    $client.Timeout = [TimeSpan]::FromSeconds(5)
                    try {
                        $response = $client.PostAsync(('http://' + $TvIp + ':8001/api/v2/applications/' +
                            [Uri]::EscapeDataString($appId)), [Net.Http.ByteArrayContent]::new([byte[]]::new(0))).GetAwaiter().GetResult()
                        $httpCode = [int]$response.StatusCode
                        if (-not $response.IsSuccessStatusCode -and $httpCode -ne 404) {
                            throw 'TV recusou app.'
                        }
                    } finally { $client.Dispose() }
                    if ($httpCode -eq 404) {
                        # Observed on this Q80A: Spotify opened despite an HTTP 404.
                        Reply $true 'Solicitação enviada; confirme a abertura na TV'
                    } else {
                        Reply $true 'Abertura solicitada'
                    }
                }
                default { throw 'Pedido inválido.' }
            }
        } catch {
            Close-TvSocket
            # Fixed errors only: .NET exceptions may contain the token-bearing WSS URL.
            Reply $false 'TV indisponível ou comando recusado. Confira rede e TV.'
        }
    }
} finally { Close-TvSocket }
