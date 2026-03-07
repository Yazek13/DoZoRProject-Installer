#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash bootstrap_ubuntu.sh"
  exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"

echo "==> Install base packages"
apt-get update
apt-get install -y \
  git \
  curl \
  ca-certificates \
  gnupg \
  lsb-release \
  openssh-client \
  nano

echo "==> Install Docker + Compose plugin"
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
fi
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker "${TARGET_USER}"

echo "==> Installed prerequisites"
echo "Check versions:"
echo "  git --version"
echo "  docker --version"
echo "  docker compose version"
echo ""
echo "Then continue with:"
echo "  sudo bash setup_ubuntu.sh"
