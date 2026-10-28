param(
    [ValidateSet('Save', 'Show')][string]$Action,
    [string]$Path = (Join-Path $PSScriptRoot '.local\pair-pin.dpapi')
)
$ErrorActionPreference = 'Stop'
$entropy = [Text.Encoding]::UTF8.GetBytes('Controle Q80A PIN local v1')
if ($Action -eq 'Save') {
    $pin = [Console]::In.ReadLine()
    if ($pin -notmatch '^\d{8}$') { throw 'PIN inválido.' }
    $plain = [Text.Encoding]::UTF8.GetBytes($pin)
    try {
        $encrypted = [Security.Cryptography.ProtectedData]::Protect(
            $plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($Path, $encrypted)
    } finally {
        [Array]::Clear($plain, 0, $plain.Length)
        $pin = $null
    }
} elseif ($Action -eq 'Show') {
    if (-not (Test-Path -LiteralPath $Path) -or
        ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalMinutes -ge 10) {
        $request = Join-Path (Split-Path -Parent $Path) 'renew-pin.request'
        [IO.File]::WriteAllText($request, '')
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            if ((Test-Path -LiteralPath $Path) -and
                ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalMinutes -lt 10) {
                $ready = $true
                break
            }
        }
        if (-not $ready) { throw 'Não foi possível gerar o PIN. Confira se o controle está em execução no Windows.' }
    }
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        [IO.File]::ReadAllBytes($Path), $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { [Console]::WriteLine([Text.Encoding]::UTF8.GetString($plain)) }
    finally { [Array]::Clear($plain, 0, $plain.Length) }
} else { throw 'Ação inválida.' }
