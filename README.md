# Local Tasks

A small PostgreSQL-backed task app that runs on Windows without Docker.

## Requirements

- PostgreSQL 17 installed locally
- PostgreSQL service running
- A PostgreSQL user that can connect to the selected database and create tables

## Run

From PowerShell in this folder:

```powershell
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGUSER = "postgres"
$env:PGDATABASE = "postgres"
powershell -ExecutionPolicy Bypass -File .\start.ps1
```

Open http://localhost:8080. The first start creates the `tasks` table automatically.

To use another database or port, change `PGDATABASE` or `APP_PORT` before starting.