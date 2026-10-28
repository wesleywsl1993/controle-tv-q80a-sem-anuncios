param([switch]$HttpTest)

$ErrorActionPreference = 'Stop'
$bindIp = Read-Host 'IPv4 deste Windows na rede local'
$subnet = Read-Host 'Sub-rede permitida em formato CIDR'
$tvIp = Read-Host 'IPv4 da TV'
$arguments = @('server.py', '--bind', $bindIp, '--subnet', $subnet, '--tv', $tvIp, '--port', '8765')
if ($HttpTest) { $arguments += '--http-test' }

Push-Location $PSScriptRoot
try { & python @arguments }
finally { Pop-Location }
