#Requires -Version 7
<#
.SYNOPSIS
    Queries HuggingFace for the latest Ornith models and their download links.

.DESCRIPTION
    Uses the HuggingFace API to search for models with "ornith" in the name,
    sorted by latest modification date. Outputs a formatted table with model
    details and direct GGUF download links.

    Sort order: "lastModified", "trending", "likes", "downloads", "createdAt" (default: "lastModified")

.PARAMETER Limit
    Maximum number of results to return (default: 20)

.PARAMETER Format
    Output format: "table", "json", "csv" (default: "table")
#>

[CmdletBinding()]
param(
    [ValidateSet("lastModified", "likes", "downloads", "createdAt")]
    [string]$SortBy = "lastModified",
    [int]$Limit = 20,

    [ValidateSet("table", "json", "csv")]
    [string]$Format = "table"
)

$baseUrl = "https://huggingface.co/api/models"

# Build URL with query parameters
$queryString = "search=ornith&sort=$SortBy&direction=-1&limit=$Limit"
$fullUrl = $baseUrl + "?" + $queryString

try {
    $response = Invoke-RestMethod -Uri $fullUrl -Method GET
} catch {
    Write-Error "Failed to query HuggingFace API: $_"
    exit 1
}

if ($response.Count -eq 0) {
    Write-Warning "No Ornith models found on HuggingFace."
    exit 0
}

$results = foreach ($model in $response) {
    $modelId = $model.id
    $downloads = $model.downloads
    $likes = $model.likes
    $modified = if ($model.lastModified) { [datetime]::Parse($model.lastModified) } else { $null }

    # Build download links for common GGUF variants
    $ggufUrl = "https://huggingface.co/$modelId/resolve/main/"

    [PSCustomObject]@{
        Model       = $modelId
        Format      = $model.pipeline_tag
        Tags        = ($model.tags -join ", ")
        Downloads   = $downloads
        Likes       = $likes
        Modified    = $modified
        HFPage      = "https://huggingface.co/$modelId"
        GGUFBase    = $ggufUrl
    }
}

switch ($Format) {
    "table" {
        $results | Format-Table -AutoSize -Property @(
            @{Label="Model"; Expression={$_.Model}},
            @{Label="Downloads"; Expression={$_.Downloads}},
            @{Label="Likes"; Expression={$_.Likes}},
            @{Label="Modified"; Expression={$_.Modified.ToString("yyyy-MM-dd")}}
        )
        Write-Host "`nFull details (HF page + GGUF base URL):" -ForegroundColor Cyan
        $results | Format-Table -AutoSize -Property @(
            "Model", "HFPage", "GGUFBase"
        )
    }
    "json" {
        $results | ConvertTo-Json -Depth 3
    }
    "csv" {
        $results | ConvertTo-Csv -NoTypeInformation
    }
}
