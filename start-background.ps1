$securePassword = Read-Host 'PostgreSQL password for the selected user' -AsSecureString
$password = '', $securePassword).Password
$scriptPath = Join-Path $PSScriptRoot 'server.ps1'
$port = if ($env:APP_PORT) { $env:APP_PORT } else { '8081' }
$logPath = Join-Path $PSScriptRoot 'server.log'

$processInfo = [Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.EnvironmentVariables['APP_PORT'] = $port
$processInfo.EnvironmentVariables['PGPASSWORD'] = $password

$process = [Diagnostics.Process]::new()
$process.StartInfo = $processInfo
$process.Start() | Out-Null
$password = $null
Write-Host "Task app started in the background on http://localhost:$port"
Write-Host "Server log: $logPath"