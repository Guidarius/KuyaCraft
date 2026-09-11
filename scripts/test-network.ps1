param([int]$Port = 22123)
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
Initialize-Artifacts
$hostOutput=Join-Path $ProjectRoot 'artifacts/network-host.txt'
$clientOutput=Join-Path $ProjectRoot 'artifacts/network-client.txt'
$hostLog=Join-Path $ProjectRoot 'artifacts/network-host.log'
$clientLog=Join-Path $ProjectRoot 'artifacts/network-client.log'
$hostProcess=$null
$clientProcess=$null
try {
    $hostArgs=@('"' + $ProjectRoot + '"','--network-worker','--host',"127.0.0.1:$Port",'--output','"' + $hostOutput + '"')
    $clientArgs=@('"' + $ProjectRoot + '"','--network-worker','--join',"127.0.0.1:$Port",'--output','"' + $clientOutput + '"')
    $hostProcess=Start-Process -FilePath $runtime -ArgumentList $hostArgs -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $hostLog -RedirectStandardError (Join-Path $ProjectRoot 'artifacts/network-host.err')
    $clientProcess=Start-Process -FilePath $runtime -ArgumentList $clientArgs -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError (Join-Path $ProjectRoot 'artifacts/network-client.err')
    # Touching .Handle caches it while the process is alive. Without this, Windows
    # PowerShell 5.1 reports $null from .ExitCode once the process has exited, and
    # $null -ne 0 fails the check no matter what the workers actually reported.
    $null=$hostProcess.Handle;$null=$clientProcess.Handle
    if (-not $hostProcess.WaitForExit(30000) -or -not $clientProcess.WaitForExit(30000)) { throw 'Network process timeout; inspect artifacts/network-*.log and .err.' }
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0) { throw 'Network process failed; inspect artifacts/network-*.log and .err.' }
    if ((Get-Content -LiteralPath $hostOutput -Raw) -cne (Get-Content -LiteralPath $clientOutput -Raw)) { throw 'Two-process network state mismatch.' }
    Get-Content -LiteralPath $hostLog
    Get-Content -LiteralPath $clientLog
    Write-Host 'PASS: real ENet host/client processes agree at every 100-tick checkpoint.'
} finally {
    foreach ($process in @($hostProcess,$clientProcess)) {
        if ($process -and -not $process.HasExited) { $process.Kill() }
    }
}
