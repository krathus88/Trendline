# Builds the Windows release app, then its installer.
#
#   .\tool\build_windows_installer.ps1
#
# Needs Inno Setup 6 (https://jrsoftware.org/isinfo.php) and
# dart_defines.json (see docs/SETUP.md). The installer is written to
# build\windows\installer\Trendline-Setup-<version>.exe.
# -SkipBuild packages the release folder already built.

param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# The version, without the build number, from pubspec.yaml.
$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)'
if (-not $line) { throw 'No version in pubspec.yaml' }
$version = $line.Matches[0].Groups[1].Value

if (-not $SkipBuild) {
  if (-not (Test-Path dart_defines.json)) {
    throw 'dart_defines.json is missing (see docs/SETUP.md section 2)'
  }
  flutter build windows --release --dart-define-from-file=dart_defines.json
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

$iscc = @(
  (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source,
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is not installed (ISCC.exe not found)' }

& $iscc "/DAppVersion=$version" windows\installer\trendline.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Write-Host "Installer: build\windows\installer\Trendline-Setup-$version.exe"
