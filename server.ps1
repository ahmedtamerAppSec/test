$ErrorActionPreference = 'Stop'

$port = if ($env:APP_PORT) { [int]$env:APP_PORT } else { 8080 }
$database = if ($env:PGDATABASE) { $env:PGDATABASE } else { 'postgres' }
$user = if ($env:PGUSER) { $env:PGUSER } else { 'postgres' }
$hostName = if ($env:PGHOST) { $env:PGHOST } else { 'localhost' }
$pgBin = 'C:\Program Files\PostgreSQL\17\bin\psql.exe'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $pgBin)) { throw "PostgreSQL client not found at $pgBin" }

function Invoke-Database {
    param([Parameter(Mandatory = $true)][string]$Sql, [hashtable]$Variables = @{})
    $arguments = @('-h', $hostName, '-U', $user, '-d', $database, '-At', '-q', '-c', $Sql)
    foreach ($key in $Variables.Keys) { $arguments += @('-v', "$key=$($Variables[$key])") }
    $output = & $pgBin @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($output | Out-String).Trim()) }
    return ($output -join "`n").Trim()
}

Invoke-Database -Sql (Get-Content (Join-Path $root 'schema.sql') -Raw) | Out-Null

function Send-Response {
    param($Context, [int]$StatusCode, [string]$Body, [string]$ContentType = 'application/json')
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "$ContentType; charset=utf-8"
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Read-Body($Request) {
    $reader = [IO.StreamReader]::new($Request.InputStream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Task app running at http://localhost:$port"
Write-Host "Database: $hostName / $database as $user"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $path = $context.Request.Url.AbsolutePath
            if ($path -eq '/api/tasks' -and $context.Request.HttpMethod -eq 'GET') {
                $json = Invoke-Database -Sql "SELECT COALESCE(json_agg(json_build_object('id', id, 'title', title, 'completed', completed) ORDER BY id DESC), '[]'::json) FROM tasks;"
                Send-Response $context 200 $json
                continue
            }
            if ($path -eq '/api/tasks' -and $context.Request.HttpMethod -eq 'POST') {
                $body = (Read-Body $context.Request | ConvertFrom-Json)
                $title = [string]$body.title
                if ([string]::IsNullOrWhiteSpace($title)) { Send-Response $context 400 '{"error":"Title is required"}'; continue }
                $json = Invoke-Database -Sql "INSERT INTO tasks (title) VALUES (trim(:'title')) RETURNING json_build_object('id', id, 'title', title, 'completed', completed);" -Variables @{ title = $title }
                Send-Response $context 201 $json
                continue
            }
            if ($path -match '^/api/tasks/(\d+)$' -and $context.Request.HttpMethod -eq 'PATCH') {
                $id = $Matches[1]
                $body = (Read-Body $context.Request | ConvertFrom-Json)
                $completed = if ($body.completed) { 'TRUE' } else { 'FALSE' }
                $json = Invoke-Database -Sql "UPDATE tasks SET completed = $completed WHERE id = $id RETURNING json_build_object('id', id, 'title', title, 'completed', completed);"
                if (-not $json) { Send-Response $context 404 '{"error":"Task not found"}' } else { Send-Response $context 200 $json }
                continue
            }
            if ($path -match '^/api/tasks/(\d+)$' -and $context.Request.HttpMethod -eq 'DELETE') {
                Invoke-Database -Sql "DELETE FROM tasks WHERE id = $($Matches[1]);" | Out-Null
                Send-Response $context 204 ''
                continue
            }
            $relative = if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
            $file = Join-Path (Join-Path $root 'public') $relative
            if (Test-Path $file -PathType Leaf) {
                $contentType = if ($file.EndsWith('.css')) { 'text/css' } else { 'text/html' }
                Send-Response $context 200 ([IO.File]::ReadAllText($file)) $contentType
            } else { Send-Response $context 404 '{"error":"Not found"}' }
        } catch { Send-Response $context 500 ((@{ error = $_.Exception.Message } | ConvertTo-Json -Compress)) }
    }
} finally { $listener.Stop(); $listener.Close() }