<#
.SYNOPSIS
  Uploads a scan report to DefectDojo from GitLab CI.

.DESCRIPTION
  Uses /api/v2/reimport-scan/ with auto_create_context=true:
    - first run: creates the Asset (product), Engagement and Test
    - later runs: updates the same Test, closing findings that disappeared
  Uses curl.exe so it works on both Windows PowerShell 5.1 and pwsh 7.

  Required CI/CD variables:  DD_URL, DD_API_KEY (masked)
  Optional CI/CD variables:  DD_ORGANIZATION (default: task), DD_ASSET (default: project name)
#>
param(
    [Parameter(Mandatory = $true)] [string]$File,
    [Parameter(Mandatory = $true)] [string]$ScanType,
    [string]$TestTitle = $ScanType
)

$ErrorActionPreference = 'Stop'

foreach ($name in 'DD_URL', 'DD_API_KEY') {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "CI/CD variable $name is not set"
    }
}

# A missing report (e.g. a scanner job failed) should not block the other uploads
if (-not (Test-Path -LiteralPath $File)) {
    Write-Warning "Report not found, skipping $ScanType upload: $File"
    exit 0
}

$organization = if ($env:DD_ORGANIZATION) { $env:DD_ORGANIZATION } else { 'task' }
$asset        = if ($env:DD_ASSET) { $env:DD_ASSET } else { $env:CI_PROJECT_NAME }
$engagement   = "GitLab CI - $env:CI_COMMIT_REF_NAME"
$endpoint     = "$($env:DD_URL.TrimEnd('/'))/api/v2/reimport-scan/"
$responseFile = Join-Path $env:TEMP ("dd-response-{0}.json" -f [guid]::NewGuid())

# API field names still use product_type / product (UI labels them Organization / Asset)
$curlArgs = @(
    '--silent', '--show-error',
    '--request', 'POST', $endpoint,
    '--header', "Authorization: Token $env:DD_API_KEY",
    '--output', $responseFile,
    '--write-out', '%{http_code}',
    '--form', "file=@$File",
    '--form', "scan_type=$ScanType",
    '--form', "test_title=$TestTitle",
    '--form', "product_type_name=$organization",
    '--form', "product_name=$asset",
    '--form', "engagement_name=$engagement",
    '--form', 'auto_create_context=true',
    '--form', 'active=true',
    '--form', 'verified=false',
    '--form', 'close_old_findings=true',
    '--form', 'minimum_severity=Info',
    '--form', "build_id=$env:CI_PIPELINE_ID",
    '--form', "commit_hash=$env:CI_COMMIT_SHA",
    '--form', "branch_tag=$env:CI_COMMIT_REF_NAME"
)

Write-Host "Uploading $ScanType ($File) -> $organization / $asset / $engagement"
$status = & curl.exe @curlArgs

if ($LASTEXITCODE -ne 0) {
    throw "curl failed (exit $LASTEXITCODE). Is DefectDojo reachable at $env:DD_URL from this runner?"
}

$body = if (Test-Path -LiteralPath $responseFile) { Get-Content -LiteralPath $responseFile -Raw } else { '' }
Remove-Item -LiteralPath $responseFile -ErrorAction SilentlyContinue

if ($status -notin @('200', '201')) {
    Write-Host $body
    throw "DefectDojo returned HTTP $status for $ScanType"
}

try {
    $result = $body | ConvertFrom-Json
    Write-Host "OK: $ScanType -> test $($result.test_id), engagement $($result.engagement_id)"
} catch {
    Write-Host "OK: $ScanType uploaded (HTTP $status)"
}