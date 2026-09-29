# Windows Server Deployment

The Docker daemon on this server is running Windows containers. The supplied `docker-compose.yml` uses Linux images for Node, Nginx, and PostgreSQL, so it requires a Linux Docker engine and cannot run on this Windows container engine.

For this server, use the existing PostgreSQL service, run the PowerShell API, and install Nginx natively.

## Start the application

From the project directory, set the PostgreSQL connection values and start the API:

```powershell
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGUSER = "postgres"
$env:PGDATABASE = "postgres"
powershell -ExecutionPolicy Bypass -File .\start.ps1
```

Keep this process running. It listens on `http://127.0.0.1:8080`.

To keep the API running after the terminal closes, use `start-background.ps1` instead. Set `APP_PORT` first if port 8080 is already occupied:

```powershell
$env:APP_PORT = "8081"
powershell -ExecutionPolicy Bypass -File .\start-background.ps1
```

## Configure Nginx

1. Install the Windows Nginx build on the server.
2. Copy `nginx.windows.conf` into the Nginx `conf` directory.
3. Replace `C:/path/to/test/public` with the absolute path to this project's `public` directory.
4. Run `nginx.exe -t` from the Nginx directory.
5. Start Nginx with `nginx.exe`.

Nginx listens on port 80, serves the frontend, and proxies `/api/` to the PowerShell API.

## Docker option

To use the existing `docker-compose.yml`, the Docker engine must run Linux containers. A separate Linux VM or Linux host is the usual Windows Server deployment choice. Do not run the Linux Compose files against the current Windows container engine.