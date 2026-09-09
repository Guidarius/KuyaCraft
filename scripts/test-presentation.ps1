param([switch]$AssetPipeline, [switch]$Benchmark)
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
Initialize-Artifacts
Push-Location $ProjectRoot
try {
    & $runtime $ProjectRoot --ui-test --width 1280 --height 720 --auto-quit 30 --screenshot artifacts/presentation-proof.png
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ((Test-Path -LiteralPath 'assets/generated/catalog.lua') -or (Test-Path -LiteralPath 'assets/generated/shieldguard.png')) {
        & $runtime $ProjectRoot --asset-viewer --width 1280 --height 720 --auto-quit 10 --screenshot artifacts/sprite-proof.png
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    if ($AssetPipeline) {
        & $runtime $ProjectRoot --asset-test --asset-samples 300 --width 1920 --height 1080 --auto-quit 100000 --screenshot artifacts/asset-test-start.png
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    if ($Benchmark) {
        & $runtime $ProjectRoot --asset-benchmark --asset-samples 600 --width 1920 --height 1080 --auto-quit 100000
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
} finally { Pop-Location }
exit 0
