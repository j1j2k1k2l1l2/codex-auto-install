[CmdletBinding()]
param(
    [string]$TargetDirectory,
    [string]$PackagePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
    $TargetDirectory = $PSScriptRoot
}

$PackageUrl = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix"
$ExpectedPackageName = "OpenAI.Codex"
$ExpectedPublisher = "CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B"
$ExpectedArchitecture = "x64"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message"
}

function Remove-GeneratedDirectory {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
    $name = [System.IO.Path]::GetFileName($fullPath)
    if ($name -notmatch '^\.codex-(update|backup)-[0-9a-f]{8}$') {
        throw "Refusing to remove unexpected directory: $fullPath"
    }

    if (-not (Test-Path -LiteralPath $fullPath)) {
        return
    }

    $extendedPath = if ($fullPath.StartsWith("\\")) {
        "\\?\UNC\" + $fullPath.Substring(2)
    }
    else {
        "\\?\" + $fullPath
    }
    Remove-Item -LiteralPath $extendedPath -Recurse -Force
}

function Stop-TargetProcesses {
    param([string]$Directory)

    $prefix = $Directory.TrimEnd("\") + "\"
    $processes = @(Get-Process | Where-Object {
        try {
            $_.Path -and $_.Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $false
        }
    })

    if ($processes.Count -eq 0) {
        return
    }

    Write-Step "Closing Codex processes from $Directory"
    $processes | ForEach-Object {
        Write-Host "Stopping $($_.ProcessName) (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force
    }
    $processes | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
}

function Restore-PreviousInstall {
    param(
        [string]$NewAppDirectory,
        [string]$BackupDirectory,
        [string]$DestinationDirectory,
        [string[]]$MovedNewItems,
        [string[]]$MovedOldItems
    )

    for ($index = $MovedNewItems.Count - 1; $index -ge 0; $index--) {
        $name = $MovedNewItems[$index]
        $destination = Join-Path $DestinationDirectory $name
        $staged = Join-Path $NewAppDirectory $name
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $staged -Force
        }
    }

    for ($index = $MovedOldItems.Count - 1; $index -ge 0; $index--) {
        $name = $MovedOldItems[$index]
        $backup = Join-Path $BackupDirectory $name
        $destination = Join-Path $DestinationDirectory $name
        if (Test-Path -LiteralPath $backup) {
            Move-Item -LiteralPath $backup -Destination $destination -Force
        }
    }
}

$target = [System.IO.Path]::GetFullPath($TargetDirectory)
$driveRoot = [System.IO.Path]::GetPathRoot($target)
if ($target.TrimEnd("\") -eq $driveRoot.TrimEnd("\")) {
    throw "Refusing to install directly into a drive root. Use a directory such as D:\Codex."
}
$target = $target.TrimEnd("\")

if (-not (Test-Path -LiteralPath $target -PathType Container)) {
    New-Item -ItemType Directory -Path $target | Out-Null
}

$parent = Split-Path -Parent $target
$runId = [Guid]::NewGuid().ToString("N").Substring(0, 8)
$stageRoot = Join-Path $parent ".codex-update-$runId"
$newApp = Join-Path $stageRoot "app"
$backupRoot = Join-Path $parent ".codex-backup-$runId"
$downloadedPackage = $null
$movedNewItems = @()
$movedOldItems = @()
$replacementStarted = $false
$replacementCompleted = $false
$preserveRecoveryDirectories = $false

try {
    if ($PackagePath) {
        $package = (Resolve-Path -LiteralPath $PackagePath).Path
        Write-Step "Using local package $package"
    }
    else {
        $downloadedPackage = Join-Path $env:TEMP "codex-$runId.msix"
        $package = $downloadedPackage
        Write-Step "Downloading the latest Codex package"
        & curl.exe `
            --fail `
            --location `
            --retry 3 `
            --retry-delay 2 `
            --connect-timeout 20 `
            --speed-limit 1024 `
            --speed-time 30 `
            --continue-at - `
            --output $package `
            $PackageUrl
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed with curl exit code $LASTEXITCODE."
        }
    }

    Write-Step "Verifying package signature"
    $signature = Get-AuthenticodeSignature -FilePath $package
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "The package signature is not valid: $($signature.Status)."
    }
    if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -ne $ExpectedPublisher) {
        throw "The package signer does not match the expected Codex publisher."
    }

    New-Item -ItemType Directory -Path $stageRoot | Out-Null
    Write-Step "Extracting package to staging directory"
    & tar.exe -xf $package -C $stageRoot AppxManifest.xml app
    if ($LASTEXITCODE -ne 0) {
        throw "Package extraction failed with tar exit code $LASTEXITCODE."
    }

    [xml]$manifest = Get-Content -LiteralPath (Join-Path $stageRoot "AppxManifest.xml") -Raw
    $identity = $manifest.Package.Identity
    if ($identity.Name -ne $ExpectedPackageName) {
        throw "Unexpected package name: $($identity.Name)."
    }
    if ($identity.Publisher -ne $ExpectedPublisher) {
        throw "Unexpected package publisher: $($identity.Publisher)."
    }
    if ($identity.ProcessorArchitecture -ne $ExpectedArchitecture) {
        throw "Unexpected package architecture: $($identity.ProcessorArchitecture)."
    }

    @("Codex.exe", "ChatGPT.exe", "resources\app.asar") | ForEach-Object {
        if (-not (Test-Path -LiteralPath (Join-Path $newApp $_) -PathType Leaf)) {
            throw "The package is missing required file: app\$_"
        }
    }

    Stop-TargetProcesses -Directory $target

    Write-Step "Installing Codex version $($identity.Version)"
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
    $replacementStarted = $true

    foreach ($item in Get-ChildItem -LiteralPath $newApp -Force) {
        $destination = Join-Path $target $item.Name
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination (Join-Path $backupRoot $item.Name)
            $movedOldItems += $item.Name
        }

        Move-Item -LiteralPath $item.FullName -Destination $destination
        $movedNewItems += $item.Name
    }

    $replacementCompleted = $true
    $action = if (Test-Path -LiteralPath (Join-Path $backupRoot "Codex.exe")) { "updated" } else { "installed" }
    Write-Host "`nCodex $($identity.Version) was $action successfully in $target" -ForegroundColor Green
}
catch {
    if ($replacementStarted -and -not $replacementCompleted) {
        Write-Host "`nUpdate failed during replacement. Restoring the previous installation..." -ForegroundColor Yellow
        try {
            Restore-PreviousInstall `
                -NewAppDirectory $newApp `
                -BackupDirectory $backupRoot `
                -DestinationDirectory $target `
                -MovedNewItems $movedNewItems `
                -MovedOldItems $movedOldItems
        }
        catch {
            $preserveRecoveryDirectories = $true
            Write-Warning "Automatic rollback also failed: $($_.Exception.Message)"
            Write-Warning "Recovery files were kept in $stageRoot and $backupRoot"
        }
    }
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
finally {
    if ($downloadedPackage -and (Test-Path -LiteralPath $downloadedPackage)) {
        Remove-Item -LiteralPath $downloadedPackage -Force -ErrorAction SilentlyContinue
    }
    if (-not $preserveRecoveryDirectories) {
        foreach ($directory in @($stageRoot, $backupRoot)) {
            try {
                Remove-GeneratedDirectory -Path $directory
            }
            catch {
                Write-Warning "Could not remove temporary directory $directory`: $($_.Exception.Message)"
            }
        }
    }
}
