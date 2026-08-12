# Swagger Endpoint Counts

PowerShell 7 script that reads Swagger/OpenAPI URLs from a JSON file and writes a delimited output file with each key and the number of endpoints in that API definition.

The script counts HTTP operations under the `paths` section for Swagger 2.0 and OpenAPI 3.x documents.

## Input JSON

The simplest input format is a JSON object where each property name is the key and each value is the Swagger/OpenAPI URL:

```json
{
  "orders": "https://example.com/orders/swagger.json",
  "billing": "https://example.com/billing/openapi.json"
}
```

You can also use an array of objects:

```json
[
  {
    "key": "orders",
    "url": "https://example.com/orders/swagger.json"
  },
  {
    "key": "billing",
    "url": "https://example.com/billing/openapi.json"
  }
]
```

## Usage

```powershell
pwsh .\count-swagger-endpoints.ps1 `
    -InputJsonPath .\swaggers.json `
    -OutputPath .\swagger-endpoint-counts.csv
```

Write a tab-delimited file:

```powershell
pwsh .\count-swagger-endpoints.ps1 `
    -InputJsonPath .\swaggers.json `
    -OutputPath .\swagger-endpoint-counts.tsv `
    -Delimiter "`t"
```

Increase the HTTP timeout:

```powershell
pwsh .\count-swagger-endpoints.ps1 `
    -InputJsonPath .\swaggers.json `
    -TimeoutSeconds 120
```

Bypass proxy settings when downloading Swagger/OpenAPI documents:

```powershell
pwsh .\count-swagger-endpoints.ps1 `
    -InputJsonPath .\swaggers.json `
    -NoProxy
```

## Output

The output file contains two columns:

```text
Key,EndpointCount
orders,42
billing,18
```

Use `-Help` to print script usage.
