param([string]$Suite = 'all', [switch]$SelfTestFailure, [switch]$DeterminismWorker, [string]$OutputPath = '', [int]$Schedule = 60)
. "$PSScriptRoot/common.ps1"
$runtime = Get-LoveRuntime
Initialize-Artifacts
$testArgs = @($ProjectRoot, '--test', $Suite)
if ($SelfTestFailure) { $testArgs += '--self-test-failure' }
if ($DeterminismWorker) { $testArgs += @('--determinism-worker', '--schedule', "$Schedule", '--output', $OutputPath) }
Push-Location $ProjectRoot
try {
    & $runtime @testArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { exit $code }
    if (-not $DeterminismWorker -and -not $SelfTestFailure -and $Suite -in @('all', 'determinism')) {
        $paths = @()
        foreach ($fps in @(30, 60, 144)) {
            $out = Join-Path $ProjectRoot "artifacts/determinism-$fps.txt"
            & $runtime $ProjectRoot --test determinism --determinism-worker --schedule $fps --output $out
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $paths += $out
        }
        $defaultJitPath = Join-Path $ProjectRoot 'artifacts/determinism-default-jit.txt'
        & $runtime $ProjectRoot --test determinism --determinism-worker --schedule 60 --output $defaultJitPath --test-jit-defaults
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $paths += $defaultJitPath
        $reference = Get-Content -LiteralPath $paths[0] -Raw
        foreach ($path in $paths) {
            if ((Get-Content -LiteralPath $path -Raw) -cne $reference) { throw "Separate-process determinism mismatch: $path" }
        }
        Write-Host 'PASS: 100,000 ticks agree at 100-tick checkpoints across fresh processes at 30/60/144 FPS schedules and default/tuned JIT caches.'
    }
    if (-not $DeterminismWorker -and -not $SelfTestFailure -and $Suite -in @('all','network')) {
        & "$PSScriptRoot/test-network.ps1"
    }
} finally { Pop-Location }
exit 0
