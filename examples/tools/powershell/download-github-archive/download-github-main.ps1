#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryName = "samplecode",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryBase = "https://github.com/hamdanfiras",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $TargetReposFolder = "~\repos",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $BranchName = "main",

    [Parameter()]
    [switch] $Force
)

$ErrorActionPreference = "Stop"

function Get-FullPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Clear-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Force | Remove-Item -Recurse -Force
}

$normalizedRepositoryBase = $RepositoryBase.TrimEnd([char[]] "/")
$escapedRepositoryName = [System.Uri]::EscapeDataString($RepositoryName)
$escapedBranchName = [System.Uri]::EscapeDataString($BranchName)
$archiveUrl = "$normalizedRepositoryBase/$escapedRepositoryName/archive/refs/heads/$escapedBranchName.zip"

$targetReposPath = Get-FullPath -Path $TargetReposFolder
$destinationPath = Join-Path -Path $targetReposPath -ChildPath $RepositoryName

$tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path -Path $tempRoot -ChildPath "archive.zip"
$extractPath = Join-Path -Path $tempRoot -ChildPath "extract"

try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
    New-Item -Path $targetReposPath -ItemType Directory -Force | Out-Null

    if (Test-Path -LiteralPath $destinationPath -PathType Container) {
        $existingItems = @(Get-ChildItem -LiteralPath $destinationPath -Force)
        if ($existingItems.Count -gt 0 -and -not $Force) {
            throw "Destination '$destinationPath' already exists and is not empty. Re-run with -Force to replace its contents."
        }

        if ($Force) {
            Clear-DirectoryContents -Path $destinationPath
        }
    }
    else {
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Downloading $archiveUrl"
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath

    Write-Host "Extracting archive"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $archiveRoot = @(Get-ChildItem -LiteralPath $extractPath -Directory)
    if ($archiveRoot.Count -ne 1) {
        throw "Expected the archive to contain exactly one top-level folder, but found $($archiveRoot.Count)."
    }

    $itemsToCopy = @(Get-ChildItem -LiteralPath $archiveRoot[0].FullName -Force)
    if ($itemsToCopy.Count -eq 0) {
        throw "The archive root '$($archiveRoot[0].FullName)' is empty."
    }

    Write-Host "Copying files to $destinationPath"
    Copy-Item -LiteralPath $itemsToCopy.FullName -Destination $destinationPath -Recurse -Force

    Write-Host "Done: $destinationPath"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
