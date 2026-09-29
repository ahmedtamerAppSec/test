# Local Tasks

A PostgreSQL-backed task list. Nginx is the only public entry point; the API runs in a Docker container and PostgreSQL runs outside the container.

## Deploy

This deployment uses a Linux-compatible Docker engine for the Node API. The current Windows container engine cannot run the `node:22-alpine` image; use a Linux Docker host or Linux GitLab runner for the API container.

Build the API image:

```powershell
docker build -f Dockerfile.api -t local-tasks-api .
```

Start it with PostgreSQL connection variables. Keep the API bound to localhost so only Nginx can reach it:

```powershell
docker run -d --name local-tasks-api --restart unless-stopped `
  -p 127.0.0.1:8083:3000 `
  -e PGHOST="your-postgres-host" `
  -e PGPORT="5432" `
  -e PGDATABASE="postgres" `
  -e PGUSER="postgres" `
  -e PGPASSWORD="your-password" `
  local-tasks-api
```

Configure native Windows Nginx with [nginx.windows.conf](nginx.windows.conf). It serves `public/` and proxies `/api/` to `127.0.0.1:8083`. Replace the `root` path with the absolute path to this project's `public` folder, then run `nginx.exe -t` and reload Nginx.

Open the app through Nginx at http://localhost/. Do not expose port 8083 publicly.

## GitLab CI

`.gitlab-ci.yml` checks the Node API and builds/pushes the Docker image to the GitLab Container Registry on the default branch. The runner must support Docker-in-Docker.

## Features

- Add tasks
- Mark tasks complete
- Delete tasks
- Clear completed tasks