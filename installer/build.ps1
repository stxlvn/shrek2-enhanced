# Builds the setup program with the .NET Framework compiler that ships with Windows.
# Usage: build.ps1 [-Out <folder>]   (default: ..\build). An optional bg.png next to this script is embedded as the window picture.
param([string]$Out = (Join-Path $PSScriptRoot '..\build'))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$a = @('/nologo', '/codepage:65001', '/target:winexe', "/out:$Out\Shrek2-Enhanced-Setup.exe",
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll')
if (Test-Path "$PSScriptRoot\bg.png") { $a += "/resource:$PSScriptRoot\bg.png,bg.png" }
$a += "$PSScriptRoot\Setup.cs", "$PSScriptRoot\Installer.cs", "$PSScriptRoot\HdPatcher.cs"
& $csc @a
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Get-Item "$Out\Shrek2-Enhanced-Setup.exe" | Select-Object FullName, Length
