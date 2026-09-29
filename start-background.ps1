if (-not $env:PGPASSWORD) {
    $securePassword = Read-Host 'PostgreSQL password for the selected user' -AsSecureString
    $env:PGPASSWORD = '', $securePassword).Password
}

$scriptPath = Join-Path $PSScriptRoot 'server.ps1'
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WindowStyle Hidden
Write-Host "Task API started on port $($env:APP_PORT)"