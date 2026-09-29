# Local Tasks

A PostgreSQL-backed task list deployed on Windows Server with a GitLab Windows shell runner. Nginx is the only public entry point; the PowerShell API listens on localhost port 8083.

## Server prerequisites

- PostgreSQL 17 running locally
- Nginx installed at `C:\nginx`
- GitLab Runner installed and registered with the `windows` tag
- Runner shell set to PowerShell

The runner account must be allowed to write to `C:\apps` and reload Nginx.

## GitLab variables

Add these CI/CD variables to the GitLab project. Mark `DEPLOY_PGPASSWORD` as masked and protected:

- `DEPLOY_PGHOST`: PostgreSQL host, normally `localhost`
- `DEPLOY_PGPORT`: normally `5432`
- `DEPLOY_PGDATABASE`: normally `postgres`
- `DEPLOY_PGUSER`: PostgreSQL username
- `DEPLOY_PGPASSWORD`: PostgreSQL password

## Deployment

Push to the default branch. `.gitlab-ci.yml` will:

1. Validate the PowerShell API and PostgreSQL client.
2. Copy the API and frontend to `C:\apps\local-tasks`.
3. Restart only this application's API process.
4. Validate and reload Nginx.
5. Check the public app at `http://localhost/`.

Nginx serves `C:\apps\local-tasks\public` and proxies `/api/` to `127.0.0.1:8083`. Port 8083 is not exposed publicly.

## Manual recovery

From the deployment directory:

```powershell
$env:APP_PORT = "8083"
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "postgres"
$env:PGUSER = "postgres"
powershell -ExecutionPolicy Bypass -File .\start-background.ps1
```

The Nginx configuration is in [nginx.windows.conf](nginx.windows.conf).