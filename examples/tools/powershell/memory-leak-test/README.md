# Memory Leak Test

PowerShell helper script for comparing Java heap dumps before and after exercising an HTTP endpoint.

The script:

1. Runs a full GC with `jcmd`.
2. Creates a baseline heap dump.
3. Calls the target URL repeatedly.
4. Runs another full GC.
5. Creates a second heap dump for comparison in Eclipse MAT or another heap analysis tool.

## Prerequisites

- PowerShell 7 or Windows PowerShell
- A running Java process to inspect
- `jcmd` available on `PATH`, or passed with `-Jcmd`
- An HTTP endpoint that triggers the behavior you want to inspect

## Usage

```powershell
pwsh .\memory-leak-test.ps1 -ProcessId 12345 -Url http://localhost:8080/dummy/leak/heap?mb=50
```

Run more calls:

```powershell
pwsh .\memory-leak-test.ps1 `
    -ProcessId 12345 `
    -Url http://localhost:8080/dummy/leak/heap?mb=50 `
    -Calls 500
```

Send a POST request:

```powershell
pwsh .\memory-leak-test.ps1 `
    -ProcessId 12345 `
    -Method POST `
    -Url http://localhost:8080/dummy/reset
```

Write heap dumps to a custom folder:

```powershell
pwsh .\memory-leak-test.ps1 `
    -ProcessId 12345 `
    -Url http://localhost:8080/dummy/leak/heap?mb=50 `
    -OutputDir D:\HeapDumps
```

## Output

By default, heap dumps are written to `.\heap-dumps`:

```text
01-before.hprof
02-after-<Calls>.hprof
```

Use `-Help` to print the full script help.

`-Pid` is still accepted as an alias for `-ProcessId`.
