# Secure VHDX

PowerShell tool for a local BitLocker-encrypted VHDX vault. The vault is a single file that can be backed up while it is dismounted.

Default vault file:

```text
%USERPROFILE%\secure.vhdx
```

## Commands

```powershell
.\secure-vhdx.ps1 create
.\secure-vhdx.ps1 mount
.\secure-vhdx.ps1 eject
.\secure-vhdx.ps1 status
```

Run without a command to get an interactive prompt:

```powershell
.\secure-vhdx.ps1
```

## Examples

Create the default 20 GB dynamic VHDX:

```powershell
.\secure-vhdx.ps1 create
```

Create a custom vault:

```powershell
.\secure-vhdx.ps1 create -Path D:\Backups\secure.vhdx -SizeGB 50
```

Mount and unlock:

```powershell
.\secure-vhdx.ps1 mount
```

Lock and eject:

```powershell
.\secure-vhdx.ps1 eject
```

If Windows reports that files are still open inside the vault, close them and run `eject` again. Use `-Force` only when you are sure nothing needs to be saved:

```powershell
.\secure-vhdx.ps1 eject -Force
```

## Safety Behavior

- `create` refuses to overwrite an existing VHDX.
- `mount` refuses to unlock a vault that is already unlocked.
- `mount` refuses a VHDX file with the read-only file attribute set.
- `mount` requests a writable VHDX attach and clears the disk read-only flag if Windows sets one.
- `mount` refuses non-BitLocker volumes.
- `eject` locks the BitLocker volume before dismounting.
- `eject` does not force-close open files unless `-Force` is supplied.
- failed `create` attempts do not automatically delete the VHDX file.

Back up the `.vhdx` file only after `eject` completes, or after `status` shows `Attached : False`.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on Windows
- Administrator PowerShell session
- BitLocker feature/cmdlets
- Hyper-V PowerShell module for `New-VHD`, `Mount-VHD`, and `Dismount-VHD`
