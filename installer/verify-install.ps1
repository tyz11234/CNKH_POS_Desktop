param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [string]$BundleDir = 'build/windows/x64/runner/Release'
)

$ErrorActionPreference = 'Stop'
$installerPath = (Resolve-Path $Installer).Path
$source = (Resolve-Path $BundleDir).Path
# This script is for a disposable CI runner. It never starts the POS app and
# never runs the uninstaller or accesses any Documents/business data directory.
$target = Join-Path ([IO.Path]::GetTempPath()) ('cnkh-installer-check-' + [guid]::NewGuid())
$log = "$target.log"
New-Item -ItemType Directory -Path $target | Out-Null
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/TASKS=', "/DIR=`"$target`"", "/LOG=`"$log`"")
foreach ($pass in 1..2) {
    # A second installation exercises an upgrade into the same directory.
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        if (Test-Path $log) { Get-Content $log }
        throw "Installer pass $pass failed with exit code $($process.ExitCode)."
    }
    $files = @(Get-ChildItem $source -Recurse -File)
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        $installed = Join-Path $target $relative
        if (-not (Test-Path $installed -PathType Leaf)) { throw "Installed bundle is missing: $relative" }
        if ((Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $installed -Algorithm SHA256).Hash) {
            throw "Installed file hash differs: $relative"
        }
    }
    Write-Host "Installation pass $pass verified $($files.Count) files; the POS application was not started."
}
