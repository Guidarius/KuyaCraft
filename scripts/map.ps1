# Tiled map tooling. Maps are authored in maps/<id>.tmx and exported to src/maps/<id>_tiled.lua,
# which the game loads through src/maps/tiled.lua.
#
#   -Mode Export    export every maps/*.tmx with Tiled (after editing a map)
#   -Mode Check     fail if a committed export differs from what Tiled produces now
#   -Mode Generate  rebuild maps/<Map>.tmx and its export from the code-authored layout in
#                   tools/tiled (-Map <id>, default twin_marches; -Force to overwrite an
#                   existing, possibly hand-edited, .tmx); writes artifacts/map-<id>.png
#
# Tiled 1.12.2 is expected at .tools/tiled-1.12.2/PFiles/Tiled/tiled.exe. It is a GUI program
# that exports without opening a window, but it can hang, so every call has a timeout.
param([ValidateSet('Export','Check','Generate')][string]$Mode = 'Export', [string]$Map = 'twin_marches', [switch]$Force)
. "$PSScriptRoot/common.ps1"
$tiled = Join-Path $ProjectRoot '.tools/tiled-1.12.2/PFiles/Tiled/tiled.exe'

function Invoke-TiledExport([string]$Source, [string]$Target) {
    $process = Start-Process -FilePath $tiled -ArgumentList '--export-map', 'lua', "`"$Source`"", "`"$Target`"" -PassThru -NoNewWindow
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw "Tiled timed out exporting $Source" }
    if (-not (Test-Path -LiteralPath $Target)) { throw "Tiled produced no export for $Source" }
}

if ($Mode -eq 'Generate') {
    $runtime = Get-LoveRuntime
    Initialize-Artifacts
    $arguments = @((Join-Path $ProjectRoot 'tools/tiled/generate'), $ProjectRoot, '--map', $Map)
    if ($Force) { $arguments += '--force' }
    & $runtime @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Map generation failed.' }
    exit 0
}

if (-not (Test-Path -LiteralPath $tiled)) {
    if ($Mode -eq 'Check') { Write-Host "SKIP map export check: Tiled not found at $tiled"; exit 0 }
    throw "Tiled not found at $tiled"
}

$maps = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'maps') -Filter '*.tmx'
$drift = @()
foreach ($map in $maps) {
    $committed = Join-Path $ProjectRoot "src/maps/$($map.BaseName)_tiled.lua"
    if ($Mode -eq 'Export') {
        Invoke-TiledExport $map.FullName $committed
        Write-Host "Exported $($map.Name) -> src/maps/$($map.BaseName)_tiled.lua"
    } else {
        # Tiled writes the tileset image path relative to wherever the export lands, so the
        # comparison copy has to sit beside the committed one or every check reports drift.
        $fresh = Join-Path $ProjectRoot "src/maps/$($map.BaseName)_tiled.check.lua"
        try {
            Invoke-TiledExport $map.FullName $fresh
            $a = (Get-Content -LiteralPath $fresh -Raw) -replace "`r`n", "`n"
            $b = if (Test-Path -LiteralPath $committed) { (Get-Content -LiteralPath $committed -Raw) -replace "`r`n", "`n" } else { '' }
            if ($a -cne $b) { $drift += $map.Name }
        } finally { Remove-Item -LiteralPath $fresh -ErrorAction SilentlyContinue }
    }
}
if ($Mode -eq 'Check') {
    if ($drift.Count -gt 0) { throw "Map export out of date for: $($drift -join ', '). Run scripts/map.ps1 -Mode Export." }
    Write-Host "PASS map exports match their .tmx sources ($($maps.Count) map(s))"
}
exit 0
