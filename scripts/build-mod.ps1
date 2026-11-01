# Builds Enhanced.u with the Level Editor's UCC.
# Usage: build-mod.ps1 -LevelEditor <folder with System\UCC.exe and System\UE2Runtime.ini> [-Out <folder>]
# The scripts are copied into the Level Editor tree (it supplies the stub packages they compile against), compiled there, and Enhanced.u is copied to -Out.
param([Parameter(Mandatory = $true)][string]$LevelEditor, [string]$Out = (Join-Path $PSScriptRoot '..\build'))
$ErrorActionPreference = 'Stop'
$le  = (Resolve-Path $LevelEditor).Path
$src = Join-Path $PSScriptRoot '..\mod\Enhanced'
if (-not (Test-Path "$le\System\UCC.exe")) { throw "System\UCC.exe not found in $le" }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
if (Test-Path "$le\Enhanced") { Remove-Item "$le\Enhanced" -Recurse -Force }
Copy-Item $src "$le\Enhanced" -Recurse
Remove-Item "$le\System\Enhanced.u", "$le\System\Save.tmp" -Force -ErrorAction SilentlyContinue
$log = Join-Path $Out 'make_enhanced.txt'
$p = Start-Process -FilePath "$le\System\UCC.exe" -ArgumentList 'make', 'ini=UE2Runtime.ini' -WorkingDirectory "$le\System" -PassThru -RedirectStandardOutput $log -WindowStyle Hidden
if (-not $p.WaitForExit(300000)) { $p.Kill(); throw 'make timeout' }
Get-Content $log | Where-Object { $_ -match 'Enhanced\\Classes' -or $_ -match '^Success|^Failure|Error' } | Select-Object -First 40
if (-not (Test-Path "$le\System\Enhanced.u")) { throw 'BUILD FAILED: no Enhanced.u (see make_enhanced.txt)' }
Copy-Item "$le\System\Enhanced.u" "$Out\Enhanced.u" -Force
"built $Out\Enhanced.u " + (Get-Item "$Out\Enhanced.u").Length + " bytes"
