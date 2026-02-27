#!/usr/bin/env bash
set -euo pipefail

# Single working setup script for clean Ubuntu + private GitHub repo.
# Steps:
# - install git/curl
# - generate deploy key
# - wait for user to add deploy key in GitHub
# - configure SSH
# - clone repo (SSH)
# - install Docker + Compose
# - create .env from install_bundle/.env.example
# - start services, run migrations
# - enable autostart + auto-update (systemd)

REPO_SSH="git@github.com:Yazek13/DoZoRProject.git"
BRANCH="master"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/setup_ubuntu.sh"
  exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
DEPLOY_DIR="${HOME_DIR}/projects/DoZoRProject"
KEY_PATH="${HOME_DIR}/.ssh/dozor_deploy"

echo "==> Install base packages (git, curl)"
apt-get update
apt-get install -y git curl ca-certificates

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
sudo -u "${TARGET_USER}" git checkout "${BRANCH}"
sudo -u "${TARGET_USER}" git reset --hard "origin/${BRANCH}"

echo "==> Install Docker + Compose"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker "${TARGET_USER}"

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
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${TARGET_USER}
WorkingDirectory=${DEPLOY_DIR}
ExecStart=/bin/bash -lc 'git fetch origin ${BRANCH} && git reset --hard origin/${BRANCH} && docker compose up -d --build && docker compose exec -T web python manage.py migrate'
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
