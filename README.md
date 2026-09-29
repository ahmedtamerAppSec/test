# Local Tasks

A small task list backed by PostgreSQL. It can run directly on Windows Server or in Docker on a Linux container engine.

## Windows Server

This path uses the existing PostgreSQL 17 Windows service and the PowerShell API.

From PowerShell in this folder:

```powershell
$env:APP_PORT = "8083"
powershell -ExecutionPolicy Bypass -File .\start-background.ps1
```

Enter the PostgreSQL password when prompted. The API then runs in the background at http://localhost:8083/.

The launcher does not save the password. Logs are written to `server.log`.

For Nginx, install the native Windows build and use [nginx.windows.conf](nginx.windows.conf). Replace its `root` path with the absolute path to this project's `public` folder. Nginx serves the frontend and proxies `/api/` to port 8083.

## Docker Compose

The supplied Compose stack runs Nginx, the Node API, and PostgreSQL together:

```powershell
docker compose up --build -d
```

Open http://localhost:8080. Stop it with:

```powershell
docker compose down
```

The Compose files use Linux images. On Windows Server, the Docker engine must be configured for Linux containers or the stack must run on a Linux host. The Windows container engine cannot run `node:alpine`, `nginx:alpine`, or `postgres:alpine`.

## Features

- Add tasks
- Mark tasks complete
- Delete individual tasks
- Clear completed tasks
- PostgreSQL-backed persistence
