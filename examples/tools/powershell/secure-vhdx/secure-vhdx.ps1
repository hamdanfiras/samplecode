#!/usr/bin/env pwsh
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet("create", "mount", "eject", "status", "help")]
    [string] $Command,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $Path = (Join-Path ([Environment]::GetFolderPath("UserProfile")) "secure.vhdx"),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 2048)]
    [int] $SizeGB = 20,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $Label = "SecureVault",

    [Parameter(Mandatory = $false)]
    [ValidateSet("XtsAes128", "XtsAes256", "Aes128", "Aes256")]
    [string] $EncryptionMethod = "XtsAes256",

    [Parameter(Mandatory = $false)]
    [ValidateRange(8, 256)]
    [int] $MinPasswordLength = 12,

    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 7200)]
    [int] $EncryptionTimeoutSeconds = 900,

    [Parameter(Mandatory = $false)]
    [switch] $Force
)

$ErrorActionPreference = "Stop"

function Show-Help {
@"
================================================================================
Secure VHDX
================================================================================

DESCRIPTION
-----------
Creates, mounts, locks, and ejects a local BitLocker-encrypted VHDX file.

Default vault file:

  $([Environment]::GetFolderPath("UserProfile"))\secure.vhdx

COMMANDS
--------
  create
      Create a dynamic VHDX, format it as NTFS, enable BitLocker, prompt for a
      new password, lock it, and dismount it.

  mount
      Attach the VHDX, prompt for the BitLocker password, and unlock the volume.

  eject
      Lock the BitLocker volume and dismount the VHDX.

  status
      Show whether the VHDX file exists, is attached, and is locked.

USAGE
-----
  .\secure-vhdx.ps1 create
  .\secure-vhdx.ps1 mount
  .\secure-vhdx.ps1 eject
  .\secure-vhdx.ps1 status

Custom file and size:

  .\secure-vhdx.ps1 create -Path D:\Backups\secure.vhdx -SizeGB 50
  .\secure-vhdx.ps1 mount  -Path D:\Backups\secure.vhdx
  .\secure-vhdx.ps1 eject  -Path D:\Backups\secure.vhdx

SAFETY
------
  - create refuses to overwrite an existing VHDX file.
  - mount refuses to unlock an already-unlocked vault.
  - eject locks the BitLocker volume before dismounting the VHDX.
  - eject does not force-close open files unless -Force is provided.

REQUIREMENTS
------------
  - Windows PowerShell 5.1 or PowerShell 7 on Windows
  - Run as Administrator
  - BitLocker feature/cmdlets
  - Hyper-V PowerShell module for New-VHD, Mount-VHD, and Dismount-VHD

================================================================================
"@
}

function Resolve-VaultPath {
    param(
        [Parameter(Mandatory)]
        [string] $InputPath
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputPath)
}

function Assert-Windows {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
        throw "This tool must be run on Windows."
    }
}

function Assert-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    $administratorRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

    if (-not $principal.IsInRole($administratorRole)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory)]
        [string[]] $Names
    )

    foreach ($name in $Names) {
        if ($null -eq (Get-Command $name -ErrorAction SilentlyContinue)) {
            throw "Required command '$name' was not found. Install/enable the required Windows feature or module."
        }
    }
}

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory)]
        [securestring] $SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-NewPassword {
    param(
        [Parameter(Mandatory)]
        [int] $MinimumLength
    )

    while ($true) {
        $password = Read-Host "New BitLocker password" -AsSecureString
        $confirmation = Read-Host "Confirm BitLocker password" -AsSecureString

        $passwordText = ConvertTo-PlainText -SecureString $password
        $confirmationText = ConvertTo-PlainText -SecureString $confirmation

        if ($passwordText.Length -lt $MinimumLength) {
            Write-Warning "Password must be at least $MinimumLength characters."
            continue
        }

        if ($passwordText -ne $confirmationText) {
            Write-Warning "Passwords do not match."
            continue
        }

        return $password
    }
}

function Read-UnlockPassword {
    return Read-Host "BitLocker password" -AsSecureString
}

function Get-DiskImageSafe {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    try {
        return Get-DiskImage -ImagePath $ImagePath -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-VhdDisk {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    $image = Get-DiskImageSafe -ImagePath $ImagePath
    if ($null -eq $image -or -not $image.Attached) {
        return $null
    }

    try {
        return $image | Get-Disk -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Assert-VaultFileWritable {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    $file = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
    if (($file.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
        throw "Vault file is marked read-only. Clear the file attribute before mounting writable: $ImagePath"
    }
}

function Ensure-DiskWritable {
    param(
        [Parameter(Mandatory)]
        [uint32] $DiskNumber
    )

    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop

    if ($disk.IsReadOnly) {
        Write-Host ""
        Write-Host "Clearing read-only flag on disk $DiskNumber ..."
        Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction Stop
        $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    }

    if ($disk.IsReadOnly) {
        throw "VHDX disk $DiskNumber is still read-only after mounting. Check storage permissions for the VHDX file."
    }

    return $disk
}

function Get-UsablePartition {
    param(
        [Parameter(Mandatory)]
        [uint32] $DiskNumber
    )

    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop |
        Where-Object {
            $_.Type -ne "Reserved" -and
            $_.Type -ne "System" -and
            $_.Size -gt 0
        } |
        Sort-Object -Property Size -Descending

    return $partitions | Select-Object -First 1
}

function Ensure-DriveLetter {
    param(
        [Parameter(Mandatory)]
        [uint32] $DiskNumber
    )

    $partition = Get-UsablePartition -DiskNumber $DiskNumber
    if ($null -eq $partition) {
        throw "No usable data partition was found on disk $DiskNumber."
    }

    if ([string]::IsNullOrWhiteSpace([string] $partition.DriveLetter)) {
        Add-PartitionAccessPath `
            -DiskNumber $partition.DiskNumber `
            -PartitionNumber $partition.PartitionNumber `
            -AssignDriveLetter | Out-Null

        $partition = Get-Partition `
            -DiskNumber $partition.DiskNumber `
            -PartitionNumber $partition.PartitionNumber
    }

    if ([string]::IsNullOrWhiteSpace([string] $partition.DriveLetter)) {
        throw "Windows did not assign a drive letter to the VHDX volume."
    }

    return ("{0}:" -f $partition.DriveLetter)
}

function Get-ExistingMountPoint {
    param(
        [Parameter(Mandatory)]
        [uint32] $DiskNumber
    )

    $partition = Get-UsablePartition -DiskNumber $DiskNumber
    if ($null -eq $partition -or [string]::IsNullOrWhiteSpace([string] $partition.DriveLetter)) {
        return $null
    }

    return ("{0}:" -f $partition.DriveLetter)
}

function Get-BitLockerVolumeSafe {
    param(
        [Parameter(Mandatory)]
        [string] $MountPoint
    )

    try {
        return Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-VaultState {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    $state = [ordered] @{
        Path = $ImagePath
        Exists = Test-Path -LiteralPath $ImagePath -PathType Leaf
        Attached = $false
        DiskNumber = $null
        MountPoint = $null
        BitLocker = $null
        LockStatus = $null
        VolumeStatus = $null
        ProtectionStatus = $null
        EncryptionPercentage = $null
    }

    if (-not $state.Exists) {
        return [pscustomobject] $state
    }

    $disk = Get-VhdDisk -ImagePath $ImagePath
    if ($null -eq $disk) {
        return [pscustomobject] $state
    }

    $state.Attached = $true
    $state.DiskNumber = $disk.Number

    try {
        $mountPoint = Get-ExistingMountPoint -DiskNumber $disk.Number
        $state.MountPoint = $mountPoint

        if ($null -ne $mountPoint) {
            $bitLockerVolume = Get-BitLockerVolumeSafe -MountPoint $mountPoint
            if ($null -ne $bitLockerVolume) {
                $state.BitLocker = $true
                $state.LockStatus = $bitLockerVolume.LockStatus
                $state.VolumeStatus = $bitLockerVolume.VolumeStatus
                $state.ProtectionStatus = $bitLockerVolume.ProtectionStatus
                $state.EncryptionPercentage = $bitLockerVolume.EncryptionPercentage
            }
            else {
                $state.BitLocker = $false
            }
        }
    }
    catch {
        $state.MountPoint = $null
    }

    return [pscustomobject] $state
}

function Write-VaultState {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    Write-Host ""
    Write-Host "Secure VHDX status"
    Write-Host "------------------"
    Write-Host "Path                  : $($State.Path)"
    Write-Host "File exists           : $($State.Exists)"
    Write-Host "Attached              : $($State.Attached)"

    if ($State.Attached) {
        Write-Host "Disk number           : $($State.DiskNumber)"
        Write-Host "Mount point           : $($State.MountPoint)"
        Write-Host "BitLocker volume      : $($State.BitLocker)"
        Write-Host "Lock status           : $($State.LockStatus)"
        Write-Host "Volume status         : $($State.VolumeStatus)"
        Write-Host "Protection status     : $($State.ProtectionStatus)"
        Write-Host "Encryption percentage : $($State.EncryptionPercentage)"
    }

    Write-Host ""
}

function Wait-BitLockerEncrypted {
    param(
        [Parameter(Mandatory)]
        [string] $MountPoint,

        [Parameter(Mandatory)]
        [int] $TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true) {
        $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

        if ($volume.VolumeStatus -eq "FullyEncrypted" -and [int] $volume.EncryptionPercentage -eq 100) {
            return $volume
        }

        if ((Get-Date) -gt $deadline) {
            throw "Timed out waiting for BitLocker encryption to complete. Current status: $($volume.VolumeStatus), $($volume.EncryptionPercentage)%."
        }

        Write-Host ("Encrypting {0}: {1}% ({2})" -f $MountPoint, $volume.EncryptionPercentage, $volume.VolumeStatus)
        Start-Sleep -Seconds 5
    }
}

function New-SecureVhdx {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    if (Test-Path -LiteralPath $ImagePath) {
        throw "Refusing to create vault because the file already exists: $ImagePath"
    }

    $parent = Split-Path -Parent $ImagePath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $password = Read-NewPassword -MinimumLength $MinPasswordLength
    $sizeBytes = [int64] $SizeGB * 1GB

    Write-Host ""
    Write-Host "Creating dynamic VHDX:"
    Write-Host "  $ImagePath"
    Write-Host "Maximum size:"
    Write-Host "  $SizeGB GB"

    try {
        New-VHD -Path $ImagePath -SizeBytes $sizeBytes -Dynamic | Out-Null

        $mountedImage = Mount-VHD -Path $ImagePath -Passthru -ReadOnly:$false
        $disk = $mountedImage | Get-Disk
        $disk = Ensure-DiskWritable -DiskNumber $disk.Number

        if ($disk.PartitionStyle -eq "RAW") {
            Initialize-Disk -Number $disk.Number -PartitionStyle GPT | Out-Null
        }

        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $Label -Confirm:$false -Force | Out-Null

        $partition = Get-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber
        $mountPoint = ("{0}:" -f $partition.DriveLetter)

        Write-Host ""
        Write-Host "Enabling BitLocker on $mountPoint ..."
        Enable-BitLocker `
            -MountPoint $mountPoint `
            -EncryptionMethod $EncryptionMethod `
            -PasswordProtector `
            -Password $password `
            -UsedSpaceOnly | Out-Null

        Wait-BitLockerEncrypted -MountPoint $mountPoint -TimeoutSeconds $EncryptionTimeoutSeconds | Out-Null

        Write-Host ""
        Write-Host "Locking and dismounting vault..."
        Lock-BitLocker -MountPoint $mountPoint -ErrorAction Stop | Out-Null
        Dismount-VHD -Path $ImagePath -ErrorAction Stop

        Write-Host ""
        Write-Host "Vault created, locked, and dismounted:"
        Write-Host "  $ImagePath"
    }
    catch {
        Write-Warning "Create failed: $($_.Exception.Message)"
        Write-Warning "The script will not delete the VHDX automatically. Inspect the file before removing it."
        throw
    }
}

function Mount-SecureVhdx {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "Vault file was not found: $ImagePath"
    }

    Assert-VaultFileWritable -ImagePath $ImagePath

    $state = Get-VaultState -ImagePath $ImagePath
    if ($state.Attached -and $state.LockStatus -eq "Unlocked") {
        throw "Vault is already mounted and unlocked at $($state.MountPoint)."
    }

    if (-not $state.Attached) {
        Write-Host ""
        Write-Host "Attaching VHDX:"
        Write-Host "  $ImagePath"
        Mount-VHD -Path $ImagePath -ReadOnly:$false | Out-Null
    }

    $disk = Get-VhdDisk -ImagePath $ImagePath
    if ($null -eq $disk) {
        throw "VHDX was not attached successfully."
    }

    $disk = Ensure-DiskWritable -DiskNumber $disk.Number
    $mountPoint = Ensure-DriveLetter -DiskNumber $disk.Number
    $bitLockerVolume = Get-BitLockerVolumeSafe -MountPoint $mountPoint

    if ($null -eq $bitLockerVolume) {
        throw "Attached volume at $mountPoint is not a BitLocker volume. Refusing to continue."
    }

    if ($bitLockerVolume.LockStatus -eq "Unlocked") {
        Write-Host ""
        Write-Host "Vault is already unlocked at $mountPoint."
        return
    }

    $password = Read-UnlockPassword

    Write-Host ""
    Write-Host "Unlocking vault at $mountPoint ..."
    Unlock-BitLocker -MountPoint $mountPoint -Password $password | Out-Null

    $bitLockerVolume = Get-BitLockerVolume -MountPoint $mountPoint
    if ($bitLockerVolume.LockStatus -ne "Unlocked") {
        throw "Vault did not unlock. Check the password and try again."
    }

    Write-Host ""
    Write-Host "Vault mounted and unlocked:"
    Write-Host "  $mountPoint\"
}

function Dismount-SecureVhdx {
    param(
        [Parameter(Mandatory)]
        [string] $ImagePath
    )

    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "Vault file was not found: $ImagePath"
    }

    $state = Get-VaultState -ImagePath $ImagePath
    if (-not $state.Attached) {
        Write-Host ""
        Write-Host "Vault is not attached. Nothing to eject."
        return
    }

    $disk = Get-VhdDisk -ImagePath $ImagePath
    if ($null -eq $disk) {
        throw "Could not read attached VHDX disk."
    }

    $mountPoint = Ensure-DriveLetter -DiskNumber $disk.Number
    $bitLockerVolume = Get-BitLockerVolumeSafe -MountPoint $mountPoint

    if ($null -eq $bitLockerVolume) {
        throw "Attached volume at $mountPoint is not a BitLocker volume. Refusing to dismount it with this tool."
    }

    if ($bitLockerVolume.LockStatus -eq "Unlocked") {
        Write-Host ""
        Write-Host "Locking vault at $mountPoint ..."

        if ($Force) {
            Lock-BitLocker -MountPoint $mountPoint -ForceDismount -ErrorAction Stop | Out-Null
        }
        else {
            Lock-BitLocker -MountPoint $mountPoint -ErrorAction Stop | Out-Null
        }
    }
    else {
        Write-Host ""
        Write-Host "Vault is already locked."
    }

    Write-Host "Dismounting VHDX..."

    Dismount-VHD -Path $ImagePath -ErrorAction Stop

    Write-Host ""
    Write-Host "Vault ejected:"
    Write-Host "  $ImagePath"
}

function Read-InteractiveCommand {
    Write-Host ""
    Write-Host "Secure VHDX"
    Write-Host "-----------"
    Write-Host "1. create"
    Write-Host "2. mount"
    Write-Host "3. eject"
    Write-Host "4. status"
    Write-Host "5. help"
    Write-Host ""

    while ($true) {
        $choice = Read-Host "Choose a command"

        switch ($choice.Trim().ToLowerInvariant()) {
            "1" { return "create" }
            "create" { return "create" }
            "2" { return "mount" }
            "mount" { return "mount" }
            "3" { return "eject" }
            "eject" { return "eject" }
            "4" { return "status" }
            "status" { return "status" }
            "5" { return "help" }
            "help" { return "help" }
            default { Write-Warning "Choose create, mount, eject, status, or help." }
        }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($Command)) {
        $Command = Read-InteractiveCommand
    }

    if ($Command -eq "help") {
        Show-Help
        exit 0
    }

    Assert-Windows
    Assert-Administrator
    Assert-CommandAvailable -Names @(
        "New-VHD",
        "Mount-VHD",
        "Dismount-VHD",
        "Get-DiskImage",
        "Get-Disk",
        "Set-Disk",
        "Initialize-Disk",
        "New-Partition",
        "Get-Partition",
        "Add-PartitionAccessPath",
        "Format-Volume",
        "Enable-BitLocker",
        "Get-BitLockerVolume",
        "Unlock-BitLocker",
        "Lock-BitLocker"
    )

    $resolvedPath = Resolve-VaultPath -InputPath $Path

    switch ($Command) {
        "create" { New-SecureVhdx -ImagePath $resolvedPath }
        "mount" { Mount-SecureVhdx -ImagePath $resolvedPath }
        "eject" { Dismount-SecureVhdx -ImagePath $resolvedPath }
        "status" { Write-VaultState -State (Get-VaultState -ImagePath $resolvedPath) }
        default { throw "Unknown command: $Command" }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
