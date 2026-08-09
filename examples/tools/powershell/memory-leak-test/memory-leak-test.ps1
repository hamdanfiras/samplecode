param(
    [Parameter(Mandatory = $false)]
    [switch]$Help,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,2147483647)]
    [int]$Pid,

    [Parameter(Mandatory = $false)]
    [string]$Url,

    [ValidateRange(1,1000000)]
    [int]$Calls = 100,

    [string]$OutputDir = ".\heap-dumps",

    [string]$Jcmd = "jcmd",

    [ValidateSet("GET","POST","PUT","PATCH","DELETE")]
    [string]$Method = "GET",

    [string]$Body = "",

    [string]$ContentType = "application/json"
)

function Show-Help {

@"
================================================================================
Memory Leak Test Helper
================================================================================

DESCRIPTION
-----------
This script automates a simple memory leak investigation by:

  1. Running a Full GC
  2. Taking a baseline heap dump
  3. Calling an HTTP endpoint multiple times
  4. Running another Full GC
  5. Taking a second heap dump

The generated heap dumps can then be compared using Eclipse MAT.

USAGE
-----

    .\memory-leak-test.ps1 -Pid <pid> -Url <url>

REQUIRED PARAMETERS
-------------------

-Pid
    Java process ID.

-Url
    URL to invoke.

OPTIONAL PARAMETERS
-------------------

-Calls
    Number of HTTP requests.

    Default:
        100

-Method
    HTTP method.

    Values:
        GET
        POST
        PUT
        PATCH
        DELETE

    Default:
        GET

-Body
    Request body (POST/PUT/PATCH).

-ContentType
    Request Content-Type.

    Default:
        application/json

-OutputDir
    Folder where heap dumps are stored.

    Default:
        .\heap-dumps

-Jcmd
    Path to jcmd executable.

    Default:
        jcmd

EXAMPLES
--------

GET

    .\memory-leak-test.ps1 `
        -Pid 12345 `
        -Url http://localhost:8080/api/orders

GET 500 Calls

    .\memory-leak-test.ps1 `
        -Pid 12345 `
        -Url http://localhost:8080/api/orders `
        -Calls 500

POST

    .\memory-leak-test.ps1 `
        -Pid 12345 `
        -Method POST `
        -Url http://localhost:8080/api/orders `
        -Body '{"name":"John"}'

Custom Output Folder

    .\memory-leak-test.ps1 `
        -Pid 12345 `
        -Url http://localhost:8080/api/orders `
        -OutputDir D:\HeapDumps

HELP

    .\memory-leak-test.ps1 -Help

OUTPUT
------

01-before.hprof
02-after-<Calls>.hprof

These files can be opened in Eclipse MAT.

================================================================================
"@

}

if ($Help) {
    Show-Help
    exit 0
}

if (-not $Pid) {
    Write-Host "Missing required parameter: -Pid"
    Write-Host "Run with -Help for usage."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Url)) {
    Write-Host "Missing required parameter: -Url"
    Write-Host "Run with -Help for usage."
    exit 1
}

$ErrorActionPreference = "Stop"

function Invoke-Jcmd {
    param([string[]]$Arguments)

    Write-Host "jcmd $Pid $($Arguments -join ' ')"

    & $Jcmd $Pid @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "jcmd failed."
    }
}

function Force-GC {
    Write-Host ""
    Write-Host "Forcing GC..."
    Invoke-Jcmd "GC.run"
}

function Heap-Dump([string]$FileName) {

    $file = Join-Path $OutputDir $FileName

    Write-Host ""
    Write-Host "Creating heap dump:"
    Write-Host "  $file"

    Invoke-Jcmd "GC.heap_dump" $file
}

function Invoke-TestRequest([int]$Number) {

    try {

        $params = @{
            Uri         = $Url
            Method      = $Method
            ErrorAction = "Stop"
        }

        if ($Body -and $Method -in @("POST","PUT","PATCH")) {
            $params.Body = $Body
            $params.ContentType = $ContentType
        }

        $response = Invoke-WebRequest @params

        Write-Host ("[{0}/{1}] HTTP {2}" -f $Number,$Calls,$response.StatusCode)
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

Write-Host ""
Write-Host "==============================================="
Write-Host " Memory Leak Test"
Write-Host "==============================================="
Write-Host "PID       : $Pid"
Write-Host "URL       : $Url"
Write-Host "Method    : $Method"
Write-Host "Calls     : $Calls"
Write-Host "Output    : $OutputDir"
Write-Host "==============================================="
Write-Host ""

Force-GC
Heap-Dump "01-before.hprof"

Write-Host ""
Write-Host "Calling API..."
Write-Host ""

for($i=1;$i -le $Calls;$i++) {
    Invoke-TestRequest $i
}

Force-GC
Heap-Dump "02-after-$Calls.hprof"

Write-Host ""
Write-Host "==============================================="
Write-Host "Done."
Write-Host ""
Write-Host "Compare these files in Eclipse MAT:"
Write-Host ""
Write-Host "  01-before.hprof"
Write-Host "  02-after-$Calls.hprof"
Write-Host "==============================================="