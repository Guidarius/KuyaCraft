param(
    [Parameter(Mandatory=$true)][string]$Base,
    [string]$Blender='blender',
    [string]$Python='python',
    [string]$Output='artifacts/mouse-guard',
    [switch]$Preview
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$folder=[IO.Path]::GetFullPath((Join-Path $root $Output))
$baseFolder=(Resolve-Path -LiteralPath $Base).Path
New-Item -ItemType Directory -Force $folder | Out-Null
$buildArgs=@('--background','--factory-startup','--python-exit-code','1','--python',(Join-Path $root 'tools/blender/mouse_guard_export.py'),'--','--base',$baseFolder,'--output',$folder)
if ($Preview) {$buildArgs+='--preview'}
& $Blender @buildArgs *> (Join-Path $folder 'build.log')
if ($LASTEXITCODE -ne 0) {throw "Guard build failed; inspect $folder/build.log"}
if (-not $Preview) {
    & $Blender --background --factory-startup --python-exit-code 1 --python (Join-Path $root 'tools/blender/verify_mouse_guard.py') -- --base $baseFolder --output $folder *> (Join-Path $folder 'verify.log')
    if ($LASTEXITCODE -ne 0) {throw "Guard verification failed; inspect $folder/verify.log"}
    & $Python (Join-Path $root 'tools/assets/mouse_base_review.py') --root $root --output $folder
    if ($LASTEXITCODE -ne 0) {throw 'Guard review generation failed'}
}
Write-Output "Guard output: $folder"
