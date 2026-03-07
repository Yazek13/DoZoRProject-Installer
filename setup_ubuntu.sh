#!/usr/bin/env bash
set -euo pipefail

# Setup script for Ubuntu after bootstrap.
# Steps:
# - check required commands
# - generate deploy key
# - wait for user to add deploy key in GitHub
# - configure SSH
# - clone repo (SSH)
# - create .env from install_bundle/.env.example
# - start services, run migrations
# - enable autostart + auto-update (systemd)

REPO_SSH="git@github.com:Yazek13/DoZoRProject.git"

choose_branch() {
  local current="${1:-}"
  case "$current" in
    dev|master)
      echo "$current"
      return 0
      ;;
  esac

  echo "Select deploy branch:"
  echo "1) dev"
  echo "2) master"
  read -r -p "Choice [1-2, default 1]: " branch_choice
  case "${branch_choice:-1}" in
    1) echo "dev" ;;
    2) echo "master" ;;
    *)
      echo "Unsupported branch choice: ${branch_choice}" >&2
      exit 1
      ;;
  esac
}

BRANCH="$(choose_branch "${1:-}")"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash setup_ubuntu.sh"
  exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
DEPLOY_DIR="${HOME_DIR}/projects/DoZoRProject"
KEY_PATH="${HOME_DIR}/.ssh/dozor_deploy"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    echo "Run first: sudo bash bootstrap_ubuntu.sh"
    exit 1
  fi
}

echo "==> Check prerequisites"
require_cmd git
require_cmd curl
require_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  echo "Missing Docker Compose plugin"
  echo "Run first: sudo bash bootstrap_ubuntu.sh"
  exit 1
fi

echo "==> Generate deploy key (if missing)"
mkdir -p "${HOME_DIR}/.ssh"
if [[ ! -f "${KEY_PATH}" ]]; then
  sudo -u "${TARGET_USER}" ssh-keygen -t ed25519 -C "dozor-deploy" -f "${KEY_PATH}" -N ""
fi
chmod 600 "${KEY_PATH}"
chmod 644 "${KEY_PATH}.pub"

echo ""
echo "==> Add this deploy key to GitHub:"
cat "${KEY_PATH}.pub"
echo ""
echo "GitHub -> Repo -> Settings -> Deploy keys -> Add deploy key"
echo "Title: dozor-server-1, Allow write access: OFF"
echo "Press Enter when done..."
read -r _

echo "==> Configure SSH"
SSH_CONFIG="${HOME_DIR}/.ssh/config"
if ! grep -q "Host github.com" "${SSH_CONFIG}" 2>/dev/null; then
  cat >> "${SSH_CONFIG}" <<EOF
Host github.com
  IdentityFile ${KEY_PATH}
  IdentitiesOnly yes
EOF
fi
chown "${TARGET_USER}:${TARGET_USER}" "${SSH_CONFIG}"
chmod 600 "${SSH_CONFIG}"

echo "==> Clone repo"
mkdir -p "$(dirname "${DEPLOY_DIR}")"
if [[ ! -d "${DEPLOY_DIR}/.git" ]]; then
  sudo -u "${TARGET_USER}" git clone "${REPO_SSH}" "${DEPLOY_DIR}"
fi
cd "${DEPLOY_DIR}"
sudo -u "${TARGET_USER}" git fetch origin "${BRANCH}"
sudo -u "${TARGET_USER}" git checkout "${BRANCH}" || sudo -u "${TARGET_USER}" git checkout -b "${BRANCH}" --track "origin/${BRANCH}"
sudo -u "${TARGET_USER}" git reset --hard "origin/${BRANCH}"

echo "==> Prepare .env"
if [[ ! -f "${DEPLOY_DIR}/.env" ]]; then
  if [[ -f "${DEPLOY_DIR}/install_bundle/.env.example" ]]; then
    cp "${DEPLOY_DIR}/install_bundle/.env.example" "${DEPLOY_DIR}/.env"
  else
    echo "Missing install_bundle/.env.example. Create .env manually."
  fi
fi

echo "==> Edit .env now"
sudo -u "${TARGET_USER}" nano "${DEPLOY_DIR}/.env"

echo "==> Ensure media directory"
mkdir -p "${DEPLOY_DIR}/media"
chown -R "${TARGET_USER}:${TARGET_USER}" "${DEPLOY_DIR}"

echo "==> Build & start services"
cd "${DEPLOY_DIR}"
sudo -u "${TARGET_USER}" docker compose up -d --build
sudo -u "${TARGET_USER}" docker compose exec -T web python manage.py migrate

echo "==> Install systemd autostart + auto-update"
cat > /etc/systemd/system/dozor.service <<EOF
[Unit]
Description=DoZoRProject (Docker Compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${TARGET_USER}
WorkingDirectory=${DEPLOY_DIR}
RemainAfterExit=yes
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/dozor-update.service <<EOF
[Unit]
Description=DoZoRProject update (git pull + deploy)
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=${TARGET_USER}
WorkingDirectory=${DEPLOY_DIR}
ExecStart=/bin/bash -lc 'git fetch origin ${BRANCH} && (git show-ref --verify --quiet refs/heads/${BRANCH} && git checkout ${BRANCH} || git checkout -b ${BRANCH} --track origin/${BRANCH}) && git reset --hard origin/${BRANCH} && docker compose up -d --build && docker compose exec -T web python manage.py migrate'
StandardOutput=append:/var/log/dozor-update.log
StandardError=append:/var/log/dozor-update.log
EOF

cat > /etc/systemd/system/dozor-update.timer <<EOF
[Unit]
Description=DoZoRProject update timer (every 15 minutes)

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Unit=dozor-update.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now dozor.service
systemctl enable --now dozor-update.timer

echo "==> Done"
echo "Check:"
echo "  systemctl status dozor.service"
echo "  systemctl status dozor-update.timer"
echo "  docker compose ps"
