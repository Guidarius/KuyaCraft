# Everything: the headless suites, the multi-process determinism and network proofs, and
# the rendered suites.
#
# This exists because scripts/test.ps1 runs no rendered code at all. tests/control_input
# and tests/presentation only execute under --ui-test, so a change to the frame loop,
# the draw path or the input layer can pass the whole of test.ps1 and still be broken.
# That happened: a frame-delta clamp silently changed the documented backlog contract and
# nothing caught it until the rendered suite was run by hand.
param([double]$PerfBudget = 0, [switch]$SkipPresentation)
. "$PSScriptRoot/common.ps1"
$failures = @()

Write-Host '=== Headless suites, determinism and network ==='
if ($PerfBudget -gt 0) { & "$PSScriptRoot/test.ps1" -Suite all -PerfBudget $PerfBudget } else { & "$PSScriptRoot/test.ps1" -Suite all }
if ($LASTEXITCODE -ne 0) { $failures += 'test.ps1' }

Write-Host '=== Rendered suites at 720p, 1080p and 2560x1080 ==='
& "$PSScriptRoot/test-ui.ps1"
if ($LASTEXITCODE -ne 0) { $failures += 'test-ui.ps1' }

if (-not $SkipPresentation) {
    Write-Host '=== Asset presentation ==='
    & "$PSScriptRoot/test-presentation.ps1"
    if ($LASTEXITCODE -ne 0) { $failures += 'test-presentation.ps1' }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Error ("Failed: " + ($failures -join ', '))
    exit 1
}
Write-Host ''
Write-Host 'PASS: headless, determinism, network and rendered suites all green.'
exit 0
