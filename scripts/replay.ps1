param([Parameter(Mandatory = $true)][string]$ReplayPath)
. "$PSScriptRoot/common.ps1"
$runtime = Get-LoveRuntime
$resolvedReplay = (Resolve-Path -LiteralPath $ReplayPath).Path
Push-Location $ProjectRoot
try { & $runtime $ProjectRoot --replay $resolvedReplay; $code = $LASTEXITCODE } finally { Pop-Location }
exit $code
