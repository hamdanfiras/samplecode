#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch] $Help,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $InputJsonPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = ".\swagger-endpoint-counts.csv",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $Delimiter = ",",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3600)]
    [int] $TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Show-Help {
@"
================================================================================
Swagger Endpoint Counts
================================================================================

DESCRIPTION
-----------
Reads Swagger/OpenAPI URLs from a JSON file and writes a delimited file with:

  Key
  EndpointCount

The endpoint count is the number of HTTP operations under the document's paths
section. Both Swagger 2.0 and OpenAPI 3.x use this structure.

INPUT JSON
----------
Object map:

  {
    "orders": "https://example.com/orders/swagger.json",
    "billing": "https://example.com/billing/openapi.json"
  }

Array:

  [
    { "key": "orders", "url": "https://example.com/orders/swagger.json" },
    { "key": "billing", "url": "https://example.com/billing/openapi.json" }
  ]

USAGE
-----
  .\count-swagger-endpoints.ps1 `
      -InputJsonPath .\swaggers.json `
      -OutputPath .\swagger-endpoint-counts.csv

Tab-delimited output:

  .\count-swagger-endpoints.ps1 `
      -InputJsonPath .\swaggers.json `
      -OutputPath .\swagger-endpoint-counts.tsv `
      -Delimiter "`t"

PARAMETERS
----------
-InputJsonPath
    Path to a JSON file containing Swagger/OpenAPI URLs.

-OutputPath
    Path to the delimited output file.

    Default:
      .\swagger-endpoint-counts.csv

-Delimiter
    Field delimiter for the output file.

    Default:
      ,

-TimeoutSeconds
    HTTP request timeout per Swagger/OpenAPI URL.

    Default:
      60

================================================================================
"@
}

function Get-FullPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-JsonPropertyValue {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Object,

        [Parameter(Mandatory)]
        [string[]] $Names
    )

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }

    return $null
}

function ConvertTo-SwaggerSourceList {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object] $JsonValue
    )

    process {
        if ($null -eq $JsonValue) {
            return
        }

        if ($JsonValue -is [array]) {
            foreach ($item in $JsonValue) {
                ConvertTo-SwaggerSourceList -JsonValue $item
            }
            return
        }

        if ($JsonValue -is [pscustomobject]) {
            $key = Get-JsonPropertyValue -Object $JsonValue -Names @("key", "name", "id")
            $url = Get-JsonPropertyValue -Object $JsonValue -Names @("url", "swaggerUrl", "openApiUrl", "openapiUrl")

            if (-not [string]::IsNullOrWhiteSpace([string] $key) -and -not [string]::IsNullOrWhiteSpace([string] $url)) {
                [pscustomobject] @{
                    Key = [string] $key
                    Url = [string] $url
                }
                return
            }

            foreach ($containerName in @("swaggers", "apis", "urls", "items")) {
                $container = $JsonValue.PSObject.Properties[$containerName]
                if ($null -ne $container) {
                    ConvertTo-SwaggerSourceList -JsonValue $container.Value
                    return
                }
            }

            foreach ($property in $JsonValue.PSObject.Properties) {
                if ($property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($property.Value)) {
                    [pscustomobject] @{
                        Key = $property.Name
                        Url = $property.Value
                    }
                }
                else {
                    Write-Warning "Skipping '$($property.Name)' because its value is not a URL string."
                }
            }
            return
        }

        throw "Unsupported JSON structure. Use an object map or an array of objects with key and url properties."
    }
}

function Get-OpenApiOperationCount {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Document
    )

    $pathsProperty = $Document.PSObject.Properties["paths"]
    if ($null -eq $pathsProperty -or $null -eq $pathsProperty.Value) {
        throw "Swagger/OpenAPI document does not contain a paths section."
    }

    $operationNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($method in @("get", "put", "post", "delete", "options", "head", "patch", "trace")) {
        [void] $operationNames.Add($method)
    }

    $count = 0
    foreach ($path in $pathsProperty.Value.PSObject.Properties) {
        if ($null -eq $path.Value) {
            continue
        }

        foreach ($operation in $path.Value.PSObject.Properties) {
            if ($operationNames.Contains($operation.Name)) {
                $count++
            }
        }
    }

    return $count
}

function ConvertTo-DelimitedField {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $Delimiter
    )

    $mustQuote = $Value.Contains($Delimiter) -or $Value.Contains('"') -or $Value.Contains("`r") -or $Value.Contains("`n")
    if (-not $mustQuote) {
        return $Value
    }

    return '"' + $Value.Replace('"', '""') + '"'
}

function ConvertTo-DelimitedLine {
    param(
        [Parameter(Mandatory)]
        [string[]] $Fields,

        [Parameter(Mandatory)]
        [string] $Delimiter
    )

    $encodedFields = foreach ($field in $Fields) {
        ConvertTo-DelimitedField -Value $field -Delimiter $Delimiter
    }

    return $encodedFields -join $Delimiter
}

if ($Help) {
    Show-Help
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InputJsonPath)) {
    Write-Host "Missing required parameter: -InputJsonPath"
    Write-Host "Run with -Help for usage."
    exit 1
}

$inputPath = Get-FullPath -Path $InputJsonPath
if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
    throw "Input JSON file '$inputPath' does not exist."
}

$outputFilePath = Get-FullPath -Path $OutputPath
$outputDirectory = Split-Path -Path $outputFilePath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

$inputJson = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json
$sources = @(ConvertTo-SwaggerSourceList -JsonValue $inputJson)
if ($sources.Count -eq 0) {
    throw "Input JSON file '$inputPath' did not contain any Swagger/OpenAPI URLs."
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add((ConvertTo-DelimitedLine -Fields @("Key", "EndpointCount") -Delimiter $Delimiter))

foreach ($source in $sources) {
    Write-Host "Reading $($source.Key): $($source.Url)"

    try {
        $response = Invoke-WebRequest -Uri $source.Url -TimeoutSec $TimeoutSeconds
        $document = $response.Content | ConvertFrom-Json
        $endpointCount = Get-OpenApiOperationCount -Document $document
    }
    catch {
        Write-Warning "Failed to count '$($source.Key)': $($_.Exception.Message)"
        $endpointCount = 0
    }

    $lines.Add((ConvertTo-DelimitedLine -Fields @([string] $source.Key, [string] $endpointCount) -Delimiter $Delimiter))
}

Set-Content -LiteralPath $outputFilePath -Value $lines -Encoding utf8

Write-Host "Done: $outputFilePath"
