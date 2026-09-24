param(
    [string]$Version = '',
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'CMX\bin'),
    [switch]$SkipSetup
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This installer requires Windows.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$releaseVersion = 'v0.2.43-nightly.20260924001945.2c6129b4c083'
if (!$Version) { $Version = $releaseVersion }
if ($Version -notmatch '^v\d+\.\d+\.\d+(-nightly\.\d{14}\.[0-9a-f]+)?$') {
    throw 'Download a published CMX installer from https://compressi.us/install.ps1.'
}
$architecture = $env:PROCESSOR_ARCHITEW6432
if (!$architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
switch ($architecture.ToUpperInvariant()) {
    'AMD64' { $arch = 'amd64' }
    'ARM64' { $arch = 'arm64' }
    default { throw "Unsupported Windows architecture: $architecture. CMX requires x64 or ARM64." }
}
$asset = "cmx-windows-$arch.exe"
$base = "https://github.com/compressius/cmx/releases/download/$Version"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('cmx-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    Write-Progress -Activity "Installing CMX $Version" -Status 'Downloading' -PercentComplete 10
    $candidate = Join-Path $scratch $asset
    Invoke-WebRequest -UseBasicParsing "$base/$asset" -OutFile $candidate
    $sumsPath = Join-Path $scratch 'SHA256SUMS'
    Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS" -OutFile $sumsPath
    # GitHub serves release assets as application/octet-stream. Windows
    # PowerShell returns that body as a byte[] from Invoke-WebRequest.Content
    # (coerced to "System.Byte[]" for [Regex]::Match), so the checksum entry
    # was never found. Read raw bytes and parse lines explicitly instead.
    $sums = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($sumsPath)).TrimStart([char]0xFEFF)
    $expected = $null
    foreach ($line in ($sums -split "\r?\n")) {
        if ($line -match '^\s*([a-fA-F0-9]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $asset) {
            $expected = $Matches[1]
            break
        }
    }
    if ($null -eq $expected) { throw "Release checksum is missing for $asset." }
    Write-Progress -Activity "Installing CMX $Version" -Status 'Verifying SHA-256' -PercentComplete 65
    $actual = (Get-FileHash $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) {
        throw 'Checksum mismatch. Nothing was installed.'
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $target = Join-Path $InstallDir 'cmx.exe'
    # Never stop an unrelated executable or overwrite a running installation.
    if (Get-Process -Name cmx -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $target }) {
        throw 'CMX is running. Close its terminal and stop its gateway, then run this installer again.'
    }
    if (Test-Path $target) {
        $backup = "$target.previous-$(Get-Date -Format yyyyMMddHHmmss)-$([Guid]::NewGuid().ToString('N'))"
        Move-Item $target $backup
    }
    try { Copy-Item $candidate $target } catch {
        if ($backup) { Move-Item $backup $target -Force }
        throw
    }
    Write-Progress -Activity "Installing CMX $Version" -Status 'Adding your shortcuts' -PercentComplete 85
    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $InstallDir).TrimStart(';'), 'User')
    }
    $env:Path = "$InstallDir;$env:Path"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'CMX.lnk'))
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = 'CMX context compression gateway'
    $shortcut.Save()
    & $target --version
    if ($LASTEXITCODE -ne 0) { throw 'CMX could not start. The previous executable was retained.' }
    Write-Progress -Activity "Installing CMX $Version" -Completed
    Write-Host "Installed to $target" -ForegroundColor Green
    Write-Host 'Open CMX from the Start menu, or type cmx in a new terminal.'
    if (!$SkipSetup) {
        & $target setup --ask-connect-ready
        if ($LASTEXITCODE -ne 0) { throw 'CMX is installed, but setup needs attention. Run cmx setup to retry.' }
        & $target harness verify
        if ($LASTEXITCODE -ne 0) {
            & $target stop | Out-Null
            throw 'Automatic configuration was rolled back because the CMX gateway was unavailable.'
        }
    }
    Write-Host 'Next: cmx status | cmx setup | cmx help'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
