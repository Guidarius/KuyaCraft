param([Parameter(Mandatory=$true)][string]$Left, [Parameter(Mandatory=$true)][string]$Right)
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
Initialize-Artifacts
$leftPath=(Resolve-Path -LiteralPath $Left).Path
$rightPath=(Resolve-Path -LiteralPath $Right).Path
& $runtime $ProjectRoot --test unit --compare-left $leftPath --compare-right $rightPath --output (Join-Path $ProjectRoot 'artifacts/state-diff.txt')
exit $LASTEXITCODE
