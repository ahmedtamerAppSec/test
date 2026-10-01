# Local Tasks

A PostgreSQL-backed task list (Node.js API + static frontend), built, scanned and
deployed by a Jenkins Multibranch Pipeline on a single Ubuntu server. Nginx is the
only public entry point; the API listens on `127.0.0.1:8083` and is never exposed.

## Pipeline

Defined in [Jenkinsfile](Jenkinsfile). Runs on the Jenkins built-in node (label
`linux`) as the `jenkins` user, for every branch; only `main` is deployed.

| Stage | What it does | Fails the build when |
|---|---|---|
| Build | `npm ci`, `npm run build`, production dependencies into `build-output/` | install or build errors |
| Secret scan (TruffleHog) | Scans the **full git history** with built-in detectors plus [trufflehog-custom.yaml](trufflehog-custom.yaml) | any finding, verified or not (`--fail`) |
| SCA (Trivy) | `trivy fs --scanners vuln` on `package-lock.json`, prints a table summary | any HIGH or CRITICAL vulnerability |
| Verify | `node --check app.js`, checks the build output | missing files or syntax errors |
| Deploy (`main` only) | rsync to `/opt/local-tasks`, restart the API, test and reload nginx, check `/health` | the app or nginx does not come up |

The two scans run in parallel. Reports are archived on every build:
`trufflehog-report.json` (redacted, it never contains secret values) and
`trivy-report.json`.

New commits are picked up by the job's periodic branch scan (every minute), since
gitlab.com cannot reach the server for webhooks.

## Deploying a change

1. Push to `main` (or merge a branch into it).
2. Within a minute Jenkins builds `main`, runs both scans and deploys.
3. Check the result in Jenkins (`local-tasks` » `main`), or on the server:
   `systemctl status local-tasks` and `curl http://localhost/health`.

If a scan fails, fix the finding (rotate and remove the secret, or upgrade the
dependency). Do not weaken the scans.

## Server layout

| What | Where |
|---|---|
| Jenkins | `/var/lib/jenkins`, systemd unit `jenkins`, port 8081 |
| Deployed app | `/opt/local-tasks` (written by `jenkins`, read-only for the app) |
| App service | systemd unit `local-tasks` ([deploy/local-tasks.service](deploy/local-tasks.service)), runs as user `localtasks` |
| App configuration | `/etc/local-tasks/app.env` (root, mode 600): `PORT`, `PG*` settings and the DB password |
| Database | PostgreSQL 16 on `127.0.0.1:5432`, database `tasks`, user `tasks_app` |
| Nginx | `/etc/nginx/sites-available/local-tasks` ([deploy/nginx.linux.conf](deploy/nginx.linux.conf)), port 80 |
| Deploy permissions | `/etc/sudoers.d/jenkins-deploy`: `jenkins` may only restart `local-tasks`, run `nginx -t` and reload nginx |
| Trivy DB cache | `/var/lib/trivy` |

## One-time server setup

Prerequisites: Jenkins, Node.js 22, nginx, PostgreSQL, TruffleHog and Trivy
installed; a `tasks` database owned by `tasks_app`.

```bash
sudo bash deploy/setup-server.sh
```

The script is idempotent. It creates the `localtasks` user, `/opt/local-tasks`,
the systemd unit, the nginx site and the sudoers rule. It writes an `app.env`
template only if none exists. Set `PGPASSWORD` there before the first deploy.

Jenkins needs the built-in node labelled `linux`, a `gitlab-repo`
username/password credential (read-only GitLab token) and a Multibranch Pipeline
job pointing at this repository.

## Manual recovery

```bash
sudo systemctl restart local-tasks
journalctl -u local-tasks -n 50
sudo nginx -t && sudo systemctl reload nginx
```
