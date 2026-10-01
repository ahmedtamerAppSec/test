# Local Tasks

A PostgreSQL-backed task list (Node.js API + static frontend), built, scanned and
deployed by a Jenkins Pipeline job on a single Ubuntu server. Nginx is the
only public entry point; the API listens on `127.0.0.1:8083` and is never exposed.

## Pipeline

Defined in [Jenkinsfile](Jenkinsfile). Runs on the Jenkins built-in node (label
`linux`) as the `jenkins` user. The job builds and deploys the `main` branch only.

| Stage | What it does | Fails the build when |
|---|---|---|
| Build | `npm ci`, `npm run build` | install or build errors |
| Secret scan (TruffleHog) | Scans the **full git history** with built-in detectors plus [trufflehog-custom.yaml](trufflehog-custom.yaml) | any finding, verified or not (`--fail`) |
| SCA (Trivy) | `trivy fs --scanners vuln` on `package-lock.json`, prints a table summary | any HIGH or CRITICAL vulnerability |
| Dockerfile lint (hadolint) | `hadolint --failure-threshold warning Dockerfile` | any warning or error |
| Build image | `podman build` (rootless, as `jenkins`) from the [Dockerfile](Dockerfile) | build errors |
| Scan image (Trivy) | `trivy image` on the built image | any HIGH or CRITICAL vulnerability |
| Verify | `node --check app.js`; starts the image and checks it runs as non-root with the app and dependencies | missing files, syntax errors, root user |
| Push to Docker Hub | Pushes `docker.io/<user>/local-tasks:<commit>` and `:latest`, records the digest | login or push errors |
| Deploy | Writes `IMAGE=<repo>@sha256:<digest>` to `/opt/local-tasks/image.env`, copies `public/` out of the image for nginx, restarts the service, reloads nginx, checks `/health` | the app or nginx does not come up |

The three source checks run in parallel. Reports are archived on every build:
`trufflehog-report.json` (redacted, it never contains secret values),
`trivy-report.json`, `trivy-image-report.json` and `image.ref` (the deployed image).

The server runs exactly the image that was scanned: it is deployed by digest, not
by tag. The service refuses any image that is not `ALLOWED_REPO@sha256:<digest>`
(see [deploy/check-image](deploy/check-image)).

New commits on `main` are picked up by SCM polling every minute (`pollSCM` in the
Jenkinsfile), since gitlab.com cannot reach the server for webhooks.

## Deploying a change

1. Push to `main` (or merge a branch into it).
2. Within a minute Jenkins builds `main`, runs the scans, builds, scans and pushes
   the image, and deploys it.
3. Check the result in Jenkins (job `local-tasks`), or on the server:
   `systemctl status local-tasks` and `curl http://localhost/health`.

If a scan fails, fix the finding (rotate and remove the secret, upgrade the
dependency or base image, fix the Dockerfile). Do not weaken the scans.

To roll back, put a previous digest into `/opt/local-tasks/image.env` (the last
one is kept in `image.env.previous`) and run `sudo systemctl restart local-tasks`.

## Server layout

| What | Where |
|---|---|
| Jenkins | `/var/lib/jenkins`, systemd unit `jenkins`, port 8081 |
| Deployed image | `/opt/local-tasks/image.env` (`IMAGE=docker.io/<user>/local-tasks@sha256:...`, written by `jenkins`) |
| Static files | `/opt/local-tasks/public`, copied from the image, served by nginx |
| App service | systemd unit `local-tasks` ([deploy/local-tasks.service](deploy/local-tasks.service)): `podman run` of the image with host networking, UID 1000, read-only root, no capabilities |
| Allowed image repository | `/etc/local-tasks/deploy.conf` (`ALLOWED_REPO=docker.io/<user>/local-tasks`, root-owned) |
| App configuration | `/etc/local-tasks/app.env` (root, mode 600): `PORT`, `PG*` settings and the DB password |
| Database | PostgreSQL 16 on `127.0.0.1:5432`, database `tasks`, user `tasks_app` |
| Nginx | `/etc/nginx/sites-available/local-tasks` ([deploy/nginx.linux.conf](deploy/nginx.linux.conf)), port 80 |
| Deploy permissions | `/etc/sudoers.d/jenkins-deploy`: `jenkins` may only restart `local-tasks`, run `nginx -t` and reload nginx |
| Trivy DB cache | `/var/lib/trivy` |
| Build images | rootless Podman storage of `jenkins` (`/var/lib/jenkins/.local/share/containers`) |

## One-time server setup

Prerequisites: Jenkins, Node.js 22, nginx, PostgreSQL, TruffleHog and Trivy
installed; a `tasks` database owned by `tasks_app`.

```bash
sudo bash deploy/setup-server.sh <dockerhub-username>
```

The script is idempotent. It installs Podman and hadolint (checksum-pinned), sets
up rootless Podman for `jenkins`, creates `/opt/local-tasks`, `deploy.conf`, the
systemd unit, the nginx site and the sudoers rule. It writes an `app.env`
template only if none exists. Set `PGPASSWORD` there before the first deploy.

Jenkins needs the built-in node labelled `linux`, a `gitlab-repo`
username/password credential (read-only GitLab token), a `dockerhub`
username/password credential (Docker Hub username and an access token with
Read & Write scope) and a Pipeline job
("Pipeline script from SCM", branch `*/main`, script path `Jenkinsfile`).

## Manual recovery

```bash
sudo systemctl restart local-tasks
journalctl -u local-tasks -n 50
sudo podman ps --filter name=local-tasks
sudo nginx -t && sudo systemctl reload nginx
```
