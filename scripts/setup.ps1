. "$PSScriptRoot/common.ps1"
$toolsDir = Join-Path $ProjectRoot '.tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
$archive = Join-Path $toolsDir $Toolchain.archive
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -Uri $Toolchain.url -OutFile $archive
}
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
if ($actual -ne $Toolchain.sha256) {
    throw "Runtime checksum mismatch. Expected $($Toolchain.sha256), got $actual. Inspect $archive before retrying."
}
Expand-Archive -LiteralPath $archive -DestinationPath $toolsDir -Force
$runtime = Get-LoveRuntime
& $runtime --version
Write-Host "Verified archive SHA-256: $actual"
Write-Host 'Setup complete. Run .\scripts\run.ps1 or .\scripts\test.ps1.'
