$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Toolchain = Get-Content -LiteralPath (Join-Path $ProjectRoot 'toolchain.json') -Raw | ConvertFrom-Json
function Get-LoveRuntime {
    $runtime = Join-Path $ProjectRoot ($Toolchain.runtimeDirectory + '/lovec.exe')
    if (-not (Test-Path -LiteralPath $runtime)) {
        throw 'Pinned LOVE runtime missing. Run .\scripts\setup.ps1 first.'
    }
    $version = & $runtime --version
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^LOVE 11\.5 \(') {
        throw "Unexpected LOVE runtime: $version"
    }
    return $runtime
}
function Initialize-Artifacts {
    New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot 'artifacts') | Out-Null
}
