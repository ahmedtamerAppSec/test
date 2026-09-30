param(
  [Parameter(Mandatory = $true)]
  [string]$File,

  [Parameter(Mandatory = $true)]
  [string]$ScanType,

  [string]$DefectDojoUrl = $env:DEFECTDOJO_URL,
  [string]$ApiToken = $env:DEFECTDOJO_API_TOKEN,
  [string]$ProductTypeName = $env:DEFECTDOJO_PRODUCT_TYPE,
  [string]$ProductName = $env:DEFECTDOJO_PRODUCT,
  [string]$EngagementName = $env:DEFECTDOJO_ENGAGEMENT
)

$ErrorActionPreference = 'Stop'

foreach ($value in @{
    DEFECTDOJO_URL = $DefectDojoUrl
    DEFECTDOJO_API_TOKEN = $ApiToken
    DEFECTDOJO_PRODUCT_TYPE = $ProductTypeName
    DEFECTDOJO_PRODUCT = $ProductName
    DEFECTDOJO_ENGAGEMENT = $EngagementName
  }.GetEnumerator()) {
  if ([string]::IsNullOrWhiteSpace($value.Value)) {
    throw "Missing required DefectDojo setting: $($value.Key)"
  }
}

if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
  throw "DefectDojo report was not found: $File"
}

$baseUrl = $DefectDojoUrl.TrimEnd('/') -replace '/dashboard$', ''
$endpoint = "$baseUrl/api/v2/import-scan/"
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Token', $ApiToken)
$multipart = New-Object System.Net.Http.MultipartFormDataContent
$fileStream = $null

try {
  foreach ($field in @{
      scan_type = $ScanType
      product_type_name = $ProductTypeName
      product_name = $ProductName
      engagement_name = $EngagementName
      auto_create_context = 'true'
      active = 'true'
      verified = 'false'
      close_old_findings = 'false'
    }.GetEnumerator()) {
    $multipart.Add((New-Object System.Net.Http.StringContent($field.Value)), $field.Key)
  }

  $fileStream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $File).Path)
  $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
  $multipart.Add($fileContent, 'file', [System.IO.Path]::GetFileName($File))

  Write-Host "Uploading $File to DefectDojo as $ScanType"
  $response = $client.PostAsync($endpoint, $multipart).GetAwaiter().GetResult()
  $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if (-not $response.IsSuccessStatusCode) {
    throw "DefectDojo import failed with HTTP $([int]$response.StatusCode): $responseBody"
  }

  $result = $responseBody | ConvertFrom-Json
  Write-Host "DefectDojo import completed: $($result.test.title)"
}
finally {
  if ($null -ne $fileStream) { $fileStream.Dispose() }
  if ($null -ne $multipart) { $multipart.Dispose() }
  $client.Dispose()
}