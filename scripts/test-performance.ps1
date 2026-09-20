# Run shipping performance in fresh processes; the warmed all-suite run is not sufficient.
param([int]$Runs = 3, [int]$Samples = 600, [double]$PerfBudget = 10, [double]$FrameBudget = 16.6666666667)
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
Initialize-Artifacts
if ($Runs -lt 1 -or $Samples -lt 1) { throw 'Runs and Samples must be positive' }
$failures=@()
Push-Location $ProjectRoot
try {
    for ($run=1; $run -le $Runs; $run++) {
        & $runtime $ProjectRoot --test balance --filter 'active performance' --perf-budget $PerfBudget 2>&1 | Tee-Object "artifacts/performance-fresh-$run.log"
        if ($LASTEXITCODE -ne 0) { $failures += "fresh simulation $run" }
    }
    foreach ($faction in @('orders','megacorp')) {
        & $runtime $ProjectRoot --ui-benchmark --balance-benchmark --benchmark-faction $faction --width 1920 --height 1080 --ui-samples $Samples --perf-budget $PerfBudget --frame-budget $FrameBudget --auto-quit 100000 2>&1 | Tee-Object "artifacts/performance-live-$faction.log"
        if ($LASTEXITCODE -ne 0) { $failures += "live $faction" }
    }
} finally { Pop-Location }
if ($failures.Count) { Write-Error ('Performance gates failed: '+($failures -join ', '));exit 1 }
Write-Host 'PASS: fresh-process simulation and both live faction frame gates.'
exit 0
