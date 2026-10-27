# Packs this repo into RS_Holsters.zip.
#
# ALWAYS DELETES THE OLD ZIP FIRST. `7z a` on an existing archive only adds
# and updates entries -- it never removes ones whose source file is gone.
# That silently left two deleted ZScript files sitting in RS_Main.zip the
# night this repo was split out, which is exactly the shape of bug that
# becomes a fatal duplicate-class crash the moment two pk3s both carry a copy
# of the same class. Delete-then-rebuild is the only version of this script
# that can't reintroduce that.
param(
  [string]$Dest = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out  = Join-Path $root 'RS_Holsters.zip'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'

if (-not (Test-Path $sevenZip)) { throw "7-Zip not found at $sevenZip" }

if (Test-Path $out) { Remove-Item $out -Force }

# EXCLUSIONS EXTENDED 2026-08-26. The shipped RS_Holsters.zip was carrying
# .claude/settings.local.json, holsterideas.txt and README.md -- none of which
# are content, and one of which is local machine config. A lump name IGNORES
# ITS EXTENSION, so anything left in the tree can shadow a real lump.
#
# STRUCTURAL NOTE: this is an EXCLUSION list, so it can only ever exclude what
# somebody thought of. That is exactly how the three files above shipped. The
# durable fix is an explicit INCLUDE list naming what belongs in the pk3 --
# see E:\mERGE\RS_VR_Unified\build.ps1 for that shape. Left as exclusions here
# because a wrong include list silently drops content and breaks the mod,
# which is worse than shipping a stray text file.
& $sevenZip a -tzip -mx=0 $out "$root\*" -r `
    '-xr!.git' '-x!.gitattributes' '-x!.gitignore' '-x!build.ps1' '-x!RS_Holsters.zip' '-x!RS_HardPoints.zip' '-xr!media' `
    '-xr!.claude' '-xr!*.md' '-x!holsterideas.txt' '-xr!*.bak' '-xr!__pycache__' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7-Zip failed with exit code $LASTEXITCODE" }

Write-Output ("built {0} ({1:N0} bytes)" -f $out, (Get-Item $out).Length)

if ($Dest -ne '') {
  Copy-Item $out $Dest -Force
  Write-Output "copied to $Dest"
}
