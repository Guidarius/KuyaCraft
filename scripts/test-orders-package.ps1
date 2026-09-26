# Smoke the actual fused executable, not only its .love archive.
param([Parameter(Mandatory=$true)][string]$Package,[string]$Replay)
$ErrorActionPreference='Stop'
$folder=(Resolve-Path -LiteralPath $Package).Path
$executable=Join-Path $folder 'LoveRTS.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Missing fused executable' }
$cases=@(@('orders','--orders-lab','--orders-test'),@('megacorp','--micro-lab'),@('review','--orders-review'))
if ($Replay) {
 Copy-Item -LiteralPath $Replay -Destination (Join-Path $folder 'artifacts/prior-combined.replay')
 $cases+= ,@('replay','--replay','artifacts/prior-combined.replay')
}
foreach ($case in $cases) {
 $name=$case[0];$arguments=@($case[1..($case.Length-1)])+@('--width','1920','--height','1080','--auto-quit','120','--screenshot',"artifacts/smoke-$name.png")
 $process=Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $folder -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $folder "artifacts/smoke-$name.log") -RedirectStandardError (Join-Path $folder "artifacts/smoke-$name-error.log")
 if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $folder "artifacts/smoke-$name.png"))) { throw "Fused smoke failed: $name ($($process.ExitCode))" }
 Write-Host "PASS fused $name"
}
