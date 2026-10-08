param(
    [string]$BundleDir = 'build/windows/x64/runner/Release',
    [string]$OutputDir = 'dist'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$bundle = (Resolve-Path (Join-Path $repo $BundleDir)).Path
$output = [IO.Path]::GetFullPath((Join-Path $repo $OutputDir))
$versionLine = Get-Content (Join-Path $repo 'pubspec.yaml') | Select-String '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
if (-not $versionLine) { throw 'pubspec.yaml must have a numeric version such as 1.10.10+38.' }
$semver = $versionLine.Matches.Groups[1].Value
$build = $versionLine.Matches.Groups[2].Value

foreach ($required in @('cnkh_pos_desktop.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets')) {
    if (-not (Test-Path (Join-Path $bundle $required))) { throw "Missing Windows release bundle entry: $required" }
}

# Bundle the redistributable CRT DLLs app-locally so installation remains per-user
# and a fresh Windows machine does not need an administrator-run VC_redist.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio vswhere.exe was not found.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio x64 C++ tools were not found.' }
$redistRoot = Join-Path $vs 'VC/Redist/MSVC'
$crt = Get-ChildItem $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (-not $crt) { throw 'The x64 Microsoft Visual C++ redistributable directory was not found.' }
Copy-Item (Join-Path $crt.FullName '*.dll') $bundle -Force
foreach ($required in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path (Join-Path $bundle $required))) { throw "Missing Visual C++ runtime: $required" }
}

$iscc = @(
    (Join-Path $env:ProgramFiles 'Inno Setup 7/ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7/ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6/ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
}
if (-not $iscc) { throw 'Inno Setup ISCC.exe was not found. Install Inno Setup 6.7.1 or newer.' }
# The compiler checks its own version in the .iss file. ISCC.exe can omit
# Windows version resources, which makes FileVersionInfo incorrectly report 0.0.0.

New-Item -ItemType Directory -Force -Path $output | Out-Null
& $iscc "/DAppVersion=$semver" "/DAppBuild=$build" "/DBundleDir=$bundle" "/DInstallerOutputDir=$output" (Join-Path $PSScriptRoot 'cnkh-pos-desktop.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
$name = "CNKH_POS_Desktop-windows-x64-v$semver-$build"
$setup = Join-Path $output "$name-Setup.exe"
if (-not (Test-Path $setup)) { throw "Missing installer: $setup" }
Write-Host "Installer created: $setup"
