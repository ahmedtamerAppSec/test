$securePassword = Read-Host 'PostgreSQL password for the selected user' -AsSecureString
$password = '', $securePassword).Password
$env:PGPASSWORD = $password
try {
    & (Join-Path $PSScriptRoot 'server.ps1')
} finally {
    Remove-Variable password -ErrorAction SilentlyContinue
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}