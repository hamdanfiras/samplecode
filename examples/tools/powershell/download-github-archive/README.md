# Download GitHub Archive

PowerShell 7 script that downloads a GitHub branch archive and extracts the repository contents into a local repos folder.

By default, it downloads:

```text
https://github.com/hamdanfiras/samplecode/archive/refs/heads/main.zip
```

And extracts the files into:

```text
~\repos\samplecode
```

The GitHub archive contains a top-level folder such as `samplecode-main`. The script removes that wrapper folder by copying only its contents into the destination folder.

## Usage

```powershell
pwsh .\download-github-main.ps1
pwsh .\download-github-main.ps1 -RepositoryName myrepo
pwsh .\download-github-main.ps1 -RepositoryName myrepo -TargetReposFolder "D:\repos"
pwsh .\download-github-main.ps1 -RepositoryName myrepo -Force
```

Use `-Force` to replace the contents of an existing non-empty destination folder.
