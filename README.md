# Local Tasks

A PostgreSQL-backed task list deployed on Windows Server with a GitLab Windows shell runner. Nginx is the only public entry point; the Node.js API listens on localhost port 8083.

## Server prerequisites

- PostgreSQL 17 running locally
- Nginx installed at `C:\nginx`
- Node.js 22 LTS installed and available as `node` and `npm`
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

DefectDojo integration uses the following masked CI/CD variables. Set
`DEFECTDOJO_URL` to the DefectDojo server URL without `/dashboard` (for
example, `http://192.168.100.179:8080`), and store the API token only in
`DEFECTDOJO_API_TOKEN`:

- `DEFECTDOJO_URL`
- `DEFECTDOJO_API_TOKEN`
- `DEFECTDOJO_PRODUCT_TYPE`
- `DEFECTDOJO_PRODUCT`
- `DEFECTDOJO_ENGAGEMENT`

The security jobs upload Semgrep, OWASP Dependency-Check, Trivy, and ZAP
reports to the configured product and engagement. Mark the token as masked
and protected in GitLab.

## Deployment

Push to the default branch. `.gitlab-ci.yml` will:

1. Build and validate the Node.js API.
2. Copy the API and frontend to `C:\apps\local-tasks`.
3. Restart only this application's API process.
4. Validate and reload Nginx.
5. Check the public app at `http://localhost/`.

Nginx serves `C:\apps\local-tasks\public` and proxies `/api/` to `127.0.0.1:8083`. Port 8083 is not exposed publicly.

## Manual recovery

From the deployment directory:

```powershell
$env:PORT = "8083"
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "postgres"
$env:PGUSER = "postgres"
npm install --omit=dev
npm start
```

The Nginx configuration is in [nginx.windows.conf](nginx.windows.conf).