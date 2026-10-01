#!/usr/bin/env bash
# One-time server setup for local-tasks on Ubuntu. Idempotent.
# Run from the repo root:
#   sudo bash deploy/setup-server.sh <dockerhub-namespace>
#
# Installs Podman and hadolint, prepares rootless Podman for 'jenkins' (builds),
# /opt/local-tasks (written by Jenkins), /etc/local-tasks/app.env (template only
# if missing), the systemd unit that runs the image, the nginx site, and a sudoers
# rule letting 'jenkins' run exactly three deploy commands.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash deploy/setup-server.sh <dockerhub-namespace>" >&2
  exit 1
fi

NAMESPACE="${1:-}"
if ! [[ "$NAMESPACE" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "Usage: sudo bash deploy/setup-server.sh <dockerhub-namespace>" >&2
  echo "The namespace is the Docker Hub username of the 'dockerhub' Jenkins credential." >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_DIR=/opt/local-tasks
ENV_DIR=/etc/local-tasks
ENV_FILE="$ENV_DIR/app.env"
JENKINS_HOME_DIR="$(getent passwd jenkins | cut -d: -f6)"

HADOLINT_VERSION=v2.15.1
HADOLINT_SHA256=c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507

id jenkins >/dev/null

# Podman (rootful for the service, rootless for Jenkins builds).
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman uidmap slirp4netns >/dev/null

# hadolint, verified against the pinned checksum.
if ! hadolint --version 2>/dev/null | grep -q "${HADOLINT_VERSION#v}"; then
  tmp="$(mktemp)"
  curl -fsSL -o "$tmp" "https://github.com/hadolint/hadolint/releases/download/$HADOLINT_VERSION/hadolint-linux-x86_64"
  echo "$HADOLINT_SHA256  $tmp" | sha256sum -c --quiet
  install -o root -g root -m 755 "$tmp" /usr/local/bin/hadolint
  rm -f "$tmp"
fi

# Rootless Podman for jenkins: subordinate IDs and a config that works without a
# systemd user session.
if ! grep -q '^jenkins:' /etc/subuid; then usermod --add-subuids 200000-265535 jenkins; fi
if ! grep -q '^jenkins:' /etc/subgid; then usermod --add-subgids 200000-265535 jenkins; fi
install -d -o jenkins -g jenkins -m 700 "$JENKINS_HOME_DIR/.config" "$JENKINS_HOME_DIR/.config/containers"
cat > "$JENKINS_HOME_DIR/.config/containers/containers.conf" <<'EOF'
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF
chown jenkins:jenkins "$JENKINS_HOME_DIR/.config/containers/containers.conf"
(cd /tmp && sudo -u jenkins podman system migrate >/dev/null 2>&1 || true)

# Deploy directory: Jenkins writes image.env and the static files nginx serves.
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

# Which image repository the service may run (Jenkins chooses the digest).
printf 'ALLOWED_REPO=docker.io/%s/local-tasks\n' "$NAMESPACE" > "$ENV_DIR/deploy.conf"
chown root:root "$ENV_DIR/deploy.conf"
chmod 644 "$ENV_DIR/deploy.conf"
install -d -o root -g root -m 755 /usr/local/lib/local-tasks
install -o root -g root -m 755 "$REPO_DIR/deploy/check-image" /usr/local/lib/local-tasks/check-image

# systemd unit: started (or restarted) by the next Jenkins deploy.
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

echo "Server setup complete. Allowed image repository: docker.io/$NAMESPACE/local-tasks"
