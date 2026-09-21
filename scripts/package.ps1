# Builds a self-contained Windows folder containing LoveRTS.exe, which is a normal
# double-clickable program: the LOVE runtime with the game archive appended to it.
#
# Generated sprite atlases are optional. They need Blender and Python with Pillow, and
# without them the game draws its procedural placeholders instead of failing, so a
# machine that cannot build them can still produce a playable package. Pass -WithAssets
# to require them and fail loudly if the toolchain is missing.
param([switch]$WithAssets,[switch]$SkipTests)
. "$PSScriptRoot/common.ps1"
$runtime = Get-LoveRuntime
$runtimeDirectory = Split-Path $runtime
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$destination = Join-Path $ProjectRoot "dist/LoveRTS-$stamp"
$stage = Join-Path $ProjectRoot "artifacts/package-$stamp"
New-Item -ItemType Directory -Force -Path $destination, $stage | Out-Null

foreach ($file in @('main.lua', 'conf.lua')) { Copy-Item -LiteralPath (Join-Path $ProjectRoot $file) -Destination $stage }
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src') -Destination $stage -Recurse
# Included so a packaged release can run the same headless regression suites.
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tests') -Destination $stage -Recurse

$generated = Join-Path $ProjectRoot 'assets/generated'
if ($WithAssets) {
    & "$PSScriptRoot/export-assets.ps1" -Mode Package -Destination $stage
} elseif (Test-Path -LiteralPath $generated) {
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'assets') | Out-Null
    Copy-Item -LiteralPath $generated -Destination (Join-Path $stage 'assets') -Recurse
    Write-Host 'Included the sprite atlases already present in assets/generated.'
} else {
    Write-Warning 'No assets/generated found. Packaging with procedural placeholder art; run scripts/export-assets.ps1 (Blender + Python/Pillow) and repackage for sprites.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $destination 'LoveRTS.love'
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive)

# A fused executable is the runtime with the archive appended. LOVE detects the appended
# archive and mounts it as the game, which is what makes the result stand alone.
$executable = Join-Path $destination 'LoveRTS.exe'
$output = [IO.File]::Create($executable)
try {
    foreach ($part in @((Join-Path $runtimeDirectory 'love.exe'), $archive)) {
        $input = [IO.File]::OpenRead($part)
        try { $input.CopyTo($output) } finally { $input.Dispose() }
    }
} finally { $output.Dispose() }

# The runtime libraries the executable loads, plus lovec.exe for headless test runs.
foreach ($name in @('SDL2.dll', 'OpenAL32.dll', 'love.dll', 'lua51.dll', 'mpg123.dll', 'msvcp120.dll', 'msvcr120.dll', 'lovec.exe', 'license.txt')) {
    $source = Join-Path $runtimeDirectory $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $destination }
    elseif ($name -notmatch 'license') { throw "Runtime component missing: $name" }
}

Copy-Item -LiteralPath (Join-Path $ProjectRoot 'README.md'), (Join-Path $ProjectRoot 'toolchain.json') -Destination $destination
foreach ($document in @('ROADMAP.md', 'STATUS.md')) { Copy-Item -LiteralPath (Join-Path $ProjectRoot $document) -Destination $destination }
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'docs') -Destination $destination -Recurse

# Replays and screenshots are written here. The game falls back to the LOVE save
# directory if this folder is not writable, so its absence is not fatal.
New-Item -ItemType Directory -Force -Path (Join-Path $destination 'artifacts') | Out-Null

$tests = @'
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path artifacts | Out-Null
& "$PSScriptRoot/lovec.exe" "$PSScriptRoot/LoveRTS.love" --test @args
exit $LASTEXITCODE
'@
[IO.File]::WriteAllText((Join-Path $destination 'RunTests.ps1'), $tests)

$readme = @"
LoveRTS
-------

Double-click LoveRTS.exe to play.
Double-click PlayMicro.cmd for the prepared five-minute controls practice scene.
Double-click PlayOrders.cmd for the cathedral army/construction practice scene.
Double-click ReviewOrders.cmd for scale, silhouette and all-sample comparisons.
The Orders art checklist is in docs/art/ORDERS_CATHEDRAL.md.
Controls/pod checks are in docs/OVERNIGHT_HANDOFF.md.

Keep every file in this folder together: LoveRTS.exe needs the DLLs beside it. You can
move or rename the folder, and you can make a desktop shortcut to LoveRTS.exe.

Replays and screenshots are written to the artifacts folder next to the executable. If
that folder cannot be written to, the game falls back to
%APPDATA%\LOVE\LoveRTS and tells you the path it used.

Controls are in README.md. Press F10 in a match for the hotkey list, and F4 for a
performance overlay.

To run the regression suites against this exact build:
    powershell -ExecutionPolicy Bypass -File RunTests.ps1 all

Built $stamp from LOVE $($Toolchain.loveVersion).
"@
[IO.File]::WriteAllText((Join-Path $destination 'HOW-TO-PLAY.txt'), $readme)

$resolvedStage=[IO.Path]::GetFullPath($stage)
$artifactRoot=[IO.Path]::GetFullPath((Join-Path $ProjectRoot 'artifacts'))+[IO.Path]::DirectorySeparatorChar
if (-not $resolvedStage.StartsWith($artifactRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Package stage escaped the artifact directory' }
Remove-Item -LiteralPath $resolvedStage -Recurse -Force
if (-not $SkipTests) {
    Write-Host 'Verifying the packaged archive runs its own unit suite...'
    & (Join-Path $destination 'lovec.exe') (Join-Path $destination 'LoveRTS.love') --test unit
    if ($LASTEXITCODE -ne 0) { throw 'Packaged build failed its unit suite.' }
}
$practice = @'
@echo off
cd /d "%~dp0"
"%~dp0LoveRTS.exe" --micro-lab --width 1920 --height 1080
'@
[IO.File]::WriteAllText((Join-Path $destination 'PlayMicro.cmd'),$practice.Replace("`r`n","`n").Replace("`n","`r`n"))
$ordersPractice=$practice.Replace('--micro-lab','--orders-lab')
$ordersReview=$practice.Replace('--micro-lab','--orders-review')
[IO.File]::WriteAllText((Join-Path $destination 'PlayOrders.cmd'),$ordersPractice.Replace("`r`n","`n").Replace("`n","`r`n"))
[IO.File]::WriteAllText((Join-Path $destination 'ReviewOrders.cmd'),$ordersReview.Replace("`r`n","`n").Replace("`n","`r`n"))
$gitSafe='safe.directory='+($ProjectRoot -replace '\\','/')
$buildInfo=[ordered]@{built=$stamp;sourceRevision=(& git -c $gitSafe -C $ProjectRoot rev-parse HEAD);
    dirty=@(& git -c $gitSafe -C $ProjectRoot status --porcelain);runtime=$Toolchain.loveVersion;
    executableSha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash;
    archiveSha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;
    assetsRequired=[bool]$WithAssets}
if (Test-Path -LiteralPath (Join-Path $generated 'catalog.lua')) {
    $buildInfo.catalogSha256=(Get-FileHash -LiteralPath (Join-Path $generated 'catalog.lua') -Algorithm SHA256).Hash
}
$buildInfo | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $destination 'BUILD-INFO.json') -Encoding utf8
Get-FileHash -LiteralPath $executable | Format-List
[IO.File]::WriteAllText((Join-Path $ProjectRoot 'artifacts/latest-package.txt'), $destination)
Write-Host "Package: $destination"
Write-Host "Play:    $executable"
