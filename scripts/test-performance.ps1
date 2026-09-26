# Run shipping performance in fresh processes; the warmed all-suite run is not sufficient.
param([int]$Runs = 3, [int]$LiveRuns = 1, [int]$Samples = 600, [double]$PerfBudget = 10, [double]$FrameBudget = 16.6666666667,
      [string]$OutputDirectory = 'artifacts', [switch]$RequireAssets)
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
Initialize-Artifacts
if ($Runs -lt 1 -or $LiveRuns -lt 1 -or $Samples -lt 1) { throw 'Runs, LiveRuns and Samples must be positive' }
$reportDirectory=[IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputDirectory))
$artifactRoot=[IO.Path]::GetFullPath((Join-Path $ProjectRoot 'artifacts'))
if ($reportDirectory -ne $artifactRoot -and -not $reportDirectory.StartsWith($artifactRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Reports must stay under artifacts' }
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$machine=@{cpu='unavailable';gpu='unavailable';memoryBytes=$null}
try {
    $machine.cpu=@(Get-CimInstance Win32_Processor | ForEach-Object Name)
    $machine.gpu=@(Get-CimInstance Win32_VideoController | ForEach-Object Name)
    $machine.memoryBytes=(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
} catch { $machine.queryError=$_.Exception.Message }
$gitSafe='safe.directory='+($ProjectRoot -replace '\\','/')
$catalog=Join-Path $ProjectRoot 'assets/generated/catalog.lua'
$manifest=@{started=(Get-Date -Format o);revision=(& git -c $gitSafe -C $ProjectRoot rev-parse HEAD);
    dirty=@(& git -c $gitSafe -C $ProjectRoot status --porcelain);machine=$machine;runtime=(& $runtime --version);
    runs=$Runs;liveRuns=$LiveRuns;samples=$Samples;simBudget=$PerfBudget;frameBudget=$FrameBudget;requireAssets=[bool]$RequireAssets;
    catalogSha256=$(if (Test-Path -LiteralPath $catalog) { (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash } else { $null })}
if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'assets/generated')) {
    $assetFiles=@(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'assets/generated') -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{path=$_.FullName.Substring($ProjectRoot.Length+1);bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    $assetFiles | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $reportDirectory 'asset-files.json') -Encoding utf8
    $manifest.assetFilesSha256=(Get-FileHash -LiteralPath (Join-Path $reportDirectory 'asset-files.json') -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDirectory 'performance-environment.json') -Encoding utf8
$failures=@()
Push-Location $ProjectRoot
try {
    for ($run=1; $run -le $Runs; $run++) {
        & $runtime $ProjectRoot --test balance --filter 'active performance' --perf-budget $PerfBudget 2>&1 | Tee-Object (Join-Path $reportDirectory "performance-fresh-$run.log")
        if ($LASTEXITCODE -ne 0) { $failures += "fresh simulation $run" }
    }
    foreach ($faction in @('orders','megacorp')) { for ($run=1; $run -le $LiveRuns; $run++) {
        $name=if ($LiveRuns -eq 1) { "performance-live-$faction" } else { "performance-live-$faction-$run" }
        $arguments=@($ProjectRoot,'--ui-benchmark','--balance-benchmark','--benchmark-faction',$faction,'--width','1920','--height','1080',
            '--ui-samples',"$Samples",'--perf-budget',"$PerfBudget",'--frame-budget',"$FrameBudget",'--auto-quit','100000')
        if ($RequireAssets) { $arguments+='--require-assets' }
        & $runtime @arguments 2>&1 | Tee-Object (Join-Path $reportDirectory "$name.log")
        if ($LASTEXITCODE -ne 0) { $failures += "live $faction run $run" }
        if (Test-Path -LiteralPath 'artifacts/balance-ui-battle.png') { Copy-Item -LiteralPath 'artifacts/balance-ui-battle.png' -Destination (Join-Path $reportDirectory "$name.png") }
    } }
} finally { Pop-Location }
if ($failures.Count) { Write-Error ('Performance gates failed: '+($failures -join ', '));exit 1 }
Write-Host 'PASS: fresh-process simulation and both live faction frame gates.'
exit 0
