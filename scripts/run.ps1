param([ValidateSet('twin_marches','the_narrows','open_reach','crossroads','river_pass','open_fields','movement_lab')][string]$Map = 'twin_marches', [string]$Faction = 'orders', [switch]$Smoke, [int]$AutoQuit = 0, [string]$HostAddress = '', [string]$JoinAddress = '', [switch]$WoodlandViewer, [switch]$AssetViewer)
. "$PSScriptRoot/common.ps1"
$runtime = Get-LoveRuntime
Initialize-Artifacts
$launchArgs = @($ProjectRoot, '--faction', $Faction, '--map', $Map)
if ($Smoke) { $launchArgs += '--smoke' }
if ($WoodlandViewer) { $launchArgs += '--woodland-viewer' }
if ($AssetViewer) { $launchArgs += '--asset-viewer' }
if ($AutoQuit -gt 0) { $launchArgs += @('--auto-quit', "$AutoQuit") }
if ($HostAddress) { $launchArgs += @('--host', $HostAddress) }
if ($JoinAddress) { $launchArgs += @('--join', $JoinAddress) }
Push-Location $ProjectRoot
try { & $runtime @launchArgs; $code = $LASTEXITCODE } finally { Pop-Location }
exit $code
