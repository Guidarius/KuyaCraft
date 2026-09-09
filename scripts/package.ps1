. "$PSScriptRoot/common.ps1"
$runtime=Get-LoveRuntime
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$destination=Join-Path $ProjectRoot "dist/LoveRTS-$stamp"
$stage=Join-Path $ProjectRoot "artifacts/package-$stamp"
New-Item -ItemType Directory -Force -Path $destination,$stage | Out-Null
foreach ($file in @('main.lua','conf.lua')) { Copy-Item -LiteralPath (Join-Path $ProjectRoot $file) -Destination $stage }
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src') -Destination $stage -Recurse
# Include tests so a packaged release can run the same headless regression suites.
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tests') -Destination $stage -Recurse
& "$PSScriptRoot/export-assets.ps1" -Mode Package -Destination $stage
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=Join-Path $destination 'LoveRTS.love'
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$archive)
Copy-Item -Path (Join-Path (Split-Path $runtime) '*') -Destination $destination -Recurse
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'README.md'),(Join-Path $ProjectRoot 'toolchain.json') -Destination $destination
foreach ($document in @('ROADMAP.md','STATUS.md')) { Copy-Item -LiteralPath (Join-Path $ProjectRoot $document) -Destination $destination }
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'docs') -Destination $destination -Recurse
$launcher=@'
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path artifacts | Out-Null
& "$PSScriptRoot/lovec.exe" "$PSScriptRoot/LoveRTS.love" @args
exit $LASTEXITCODE
'@
[IO.File]::WriteAllText((Join-Path $destination 'Play.ps1'),$launcher)
Get-FileHash -LiteralPath $archive | Format-List
[IO.File]::WriteAllText((Join-Path $ProjectRoot 'artifacts/latest-package.txt'),$destination)
Write-Host "Package: $destination"
