#!/usr/bin/env bash
# One-time server setup for local-tasks on Ubuntu. Idempotent.
# Run from the repo root:  sudo bash deploy/setup-server.sh
#
# Creates the 'localtasks' app user, /opt/local-tasks (written by Jenkins),
# /etc/local-tasks/app.env (template only if missing), the systemd unit, the nginx
# site, and a sudoers rule letting 'jenkins' run exactly three deploy commands.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash deploy/setup-server.sh" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_USER=localtasks
DEPLOY_DIR=/opt/local-tasks
ENV_DIR=/etc/local-tasks
ENV_FILE="$ENV_DIR/app.env"

id jenkins >/dev/null

# App user: no login shell, no home directory.
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$APP_USER"
fi

# Deploy directory: Jenkins writes, the app and nginx only read.
install -d -o jenkins -g jenkins -m 755 "$DEPLOY_DIR"

# Environment file: never overwritten, since it holds the real DB password.
install -d -o root -g root -m 755 "$ENV_DIR"
if [ ! -e "$ENV_FILE" ]; then
  install -o root -g root -m 600 /dev/null "$ENV_FILE"
  cat > "$ENV_FILE" <<'EOF'
NODE_ENV=production
PORT=8083
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=tasks
PGUSER=tasks_app
PGPASSWORD=
EOF
  echo "Created $ENV_FILE template: set PGPASSWORD before the first deploy."
fi
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

# systemd unit: enabled now, started by the first Jenkins deploy.
install -o root -g root -m 644 "$REPO_DIR/deploy/local-tasks.service" /etc/systemd/system/local-tasks.service
systemctl daemon-reload
systemctl enable local-tasks

# nginx site; the stock 'default' site also claims default_server on port 80.
install -o root -g root -m 644 "$REPO_DIR/deploy/nginx.linux.conf" /etc/nginx/sites-available/local-tasks
ln -sfn /etc/nginx/sites-available/local-tasks /etc/nginx/sites-enabled/local-tasks
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# sudoers: validated before it is installed.
tmp="$(mktemp)"
cat > "$tmp" <<'EOF'
# Managed by local-tasks deploy/setup-server.sh
Cmnd_Alias LOCALTASKS_DEPLOY = /usr/bin/systemctl restart local-tasks, /usr/sbin/nginx -t, /usr/bin/systemctl reload nginx
jenkins ALL=(root) NOPASSWD: LOCALTASKS_DEPLOY
EOF
visudo -cf "$tmp"
install -o root -g root -m 440 "$tmp" /etc/sudoers.d/jenkins-deploy
rm -f "$tmp"

echo "Server setup complete."
