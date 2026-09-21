param(
    [ValidateSet('Build','Preview','Inspect','Validate','Legacy','Package')][string]$Mode = 'Build',
    [string[]]$Unit,
    [ValidateSet('bastion','woodland','megacorp_aircraft','megacorp_infantry','megacorp_buildings','megacorp_props','orders_units','orders_buildings')][string]$Roster = 'bastion',
    [string]$SourceBlend,
    [string]$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe',
    [string]$Python = $env:ASSET_PYTHON,
    [string]$Destination,
    [switch]$Force
)
. "$PSScriptRoot/common.ps1"
$candidates = @()
if ($Python) { $candidates += $Python }
$candidates += (Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$pathPython = Get-Command python -ErrorAction SilentlyContinue
if ($pathPython) { $candidates += $pathPython.Source }
$selectedPython = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
        & $candidate -c 'import PIL' 2>$null
        if ($LASTEXITCODE -eq 0) { $selectedPython = $candidate; break }
    }
}
if (-not $selectedPython) { throw 'Python 3.10+ with Pillow is required. Pass -Python or set ASSET_PYTHON.' }
$assetArgs = @((Join-Path $ProjectRoot 'tools/assets/build.py'),'--root',$ProjectRoot,'--mode',$Mode.ToLowerInvariant(),'--roster',$Roster,'--blender',$Blender)
foreach ($assetUnit in $Unit) { $assetArgs += @('--unit',$assetUnit) }
if ($SourceBlend) { $assetArgs += @('--source',$SourceBlend) }
if ($Destination) { $assetArgs += @('--destination',$Destination) }
if ($Force) { $assetArgs += '--force' }
& $selectedPython @assetArgs
if ($LASTEXITCODE -ne 0) { throw 'Asset command failed. Inspect artifacts/asset-build/latest-report.json and per-unit Blender logs.' }
