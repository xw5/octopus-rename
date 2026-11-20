# Package the release zip for Octopus Rename.
# Called by build.bat:  build.bat release
#   -> powershell -File tools\package.ps1 -Version <x.y.z>
# Output: release\OctopusRename-v<x.y.z>-win64.zip containing the renamed exe + README.md
param(
  [Parameter(Mandatory = $true)][string]$Version
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot   # tools\.. -> repo root

# App display name built from Unicode code points so this script stays pure ASCII
# (avoids codepage mojibake regardless of how the file is saved): 0x7AE0 0x9C7C 0x91CD 0x547D 0x540D
$appName = -join [char[]](0x7AE0, 0x9C7C, 0x91CD, 0x547D, 0x540D)

$exe = Join-Path $repoRoot 'bin\fprename_gui.exe'
if (-not (Test-Path $exe)) { throw "exe not found: $exe" }

$releaseDir = Join-Path $repoRoot 'release'
if (-not (Test-Path $releaseDir)) { New-Item -ItemType Directory -Path $releaseDir | Out-Null }

# Stage files to distribute (exe renamed to the app display name)
$stageExe = Join-Path $releaseDir ($appName + '.exe')
Copy-Item $exe $stageExe -Force
$stageReadme = Join-Path $releaseDir 'README.md'
Copy-Item (Join-Path $repoRoot 'README.md') $stageReadme -Force

$zip = Join-Path $releaseDir ('OctopusRename-v' + $Version + '-win64.zip')
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stageExe, $stageReadme -DestinationPath $zip

# Keep only the zip in release\
Remove-Item $stageExe, $stageReadme -Force

Write-Host ('RELEASE OK: release\OctopusRename-v' + $Version + '-win64.zip')
