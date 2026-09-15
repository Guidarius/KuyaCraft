param(
    [Parameter(Mandatory=$true)][string]$SourceBlend,
    [string]$Blender = 'blender',
    [string]$Python = 'python',
    [string]$Output = 'artifacts/mouse-base',
    [switch]$Preview
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$folder=[IO.Path]::GetFullPath((Join-Path $root $Output))
New-Item -ItemType Directory -Force $folder | Out-Null
$buildArgs=@('--background','--factory-startup','--python-exit-code','1','--python',(Join-Path $root 'tools/blender/mouse_base_export.py'),'--','--root',$root,'--source',$SourceBlend,'--output',$folder)
if ($Preview) {$buildArgs+='--preview'}
& $Blender @buildArgs *> (Join-Path $folder 'build.log')
if ($LASTEXITCODE -ne 0) {throw "Mouse build failed; inspect $folder/build.log"}
if (-not $Preview) {
    & $Blender --background --factory-startup --python-exit-code 1 --python (Join-Path $root 'tools/blender/verify_mouse_base.py') -- --source $SourceBlend --output $folder *> (Join-Path $folder 'verify.log')
    if ($LASTEXITCODE -ne 0) {throw "Mouse verification failed; inspect $folder/verify.log"}
    & $Python (Join-Path $root 'tools/assets/mouse_base_review.py') --root $root --output $folder
    if ($LASTEXITCODE -ne 0) {throw 'Mouse review generation failed'}
}
Write-Output "Mouse output: $folder"
