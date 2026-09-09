param([switch]$Benchmark)
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
Initialize-Artifacts
Push-Location $ProjectRoot
try {
    foreach ($size in @(@(1280,720),@(1920,1080),@(2560,1080))) {
        & $runtime $ProjectRoot --ui-test --width $size[0] --height $size[1] --auto-quit 10 --screenshot "artifacts/ui-$($size[0]).png"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    if ($Benchmark) {
        & $runtime $ProjectRoot --ui-benchmark --width 1920 --height 1080 --auto-quit 100000
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
} finally { Pop-Location }
exit 0
