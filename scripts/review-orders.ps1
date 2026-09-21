# Capture the real shader/camera review surfaces, then exercise normal Orders rendering.
param()
. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
$review=Join-Path $ProjectRoot 'artifacts/orders/review'
New-Item -ItemType Directory -Force -Path $review | Out-Null
Push-Location $ProjectRoot
try {
 foreach ($page in @(1,2,4)) { foreach ($mode in @(0,1,2)) {
  & $runtime $ProjectRoot --orders-review --review-page $page --review-mode $mode --width 1920 --height 1080 --auto-quit 8 --screenshot "artifacts/orders/review/page-$page-mode-$mode.png"
  if ($LASTEXITCODE -ne 0) { throw "Orders review failed: page $page mode $mode" }
 } }
 foreach ($unit in 1..6) {
  & $runtime $ProjectRoot --orders-review --review-page 3 --review-unit $unit --width 1920 --height 1080 --auto-quit 8 --screenshot "artifacts/orders/review/poses-$unit.png"
  if ($LASTEXITCODE -ne 0) { throw "Orders pose review failed: unit $unit" }
 }
 & $runtime $ProjectRoot --orders-lab --orders-test --width 1920 --height 1080 --auto-quit 120 --screenshot artifacts/orders/review/playable-orders.png
 if ($LASTEXITCODE -ne 0) { throw 'Orders rendered presentation checks failed' }
} finally { Pop-Location }
