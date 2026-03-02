# DoZoRProject Installer

Подробная инструкция для развёртывания `DoZoRProject` на новой Ubuntu (без установочных скриптов).

## Важно
- Сначала запускаются `db`, `web`, `bot_poller`.
- Затем выполняется авторизация Telegram-сессии через веб.
- Только после этого запускается `telethon_worker`.
- В этой инструкции проект запускается в Docker. `Python .venv` на сервере создавать не нужно.

Если Telegram-сессия не авторизована, `telethon_worker` нормально работать не будет.

## 1) Установка базовых пакетов
```bash
sudo apt update
sudo apt install -y git curl ca-certificates gnupg lsb-release
```

## 2) Подготовка SSH-ключа для приватного репозитория
Создать ключ:
```bash
ssh-keygen -t ed25519 -C "dozor-deploy" -f ~/.ssh/dozor_deploy
chmod 600 ~/.ssh/dozor_deploy
chmod 644 ~/.ssh/dozor_deploy.pub
cat ~/.ssh/dozor_deploy.pub
```

Добавить ключ в GitHub:
1. Откройте `Yazek13/DoZoRProject -> Settings -> Deploy keys`.
2. Нажмите `Add deploy key`.
3. `Title`: например `dozor-server-1`.
4. В поле `Key` вставьте содержимое `~/.ssh/dozor_deploy.pub`.
5. `Allow write access` оставьте выключенным.

### 2.1 Настроить SSH-клиент (Вариант A: через `nano`)
1. Откройте файл:
```bash
nano ~/.ssh/config
```
2. Вставьте:
```text
Host github.com
  IdentityFile ~/.ssh/dozor_deploy
  IdentitiesOnly yes
```
3. Сохраните файл:
- `Ctrl + O`
- `Enter`
- `Ctrl + X`
4. Поставьте права и проверьте:
```bash
chmod 600 ~/.ssh/config
ssh -T git@github.com
```

### 2.2 Настроить SSH-клиент (Вариант B: скриптом)
```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
  IdentityFile ~/.ssh/dozor_deploy
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
ssh -T git@github.com
```

Ожидаемо увидеть сообщение вида: `Hi <user/repo>! You've successfully authenticated...`.

Если при первом подключении спросит:
`Are you sure you want to continue connecting (yes/no/[fingerprint])?`
нужно ввести: `yes`.

## 3) Клонирование проекта
```bash
mkdir -p ~/projects
cd ~/projects
git clone git@github.com:Yazek13/DoZoRProject.git
cd DoZoRProject
```

## 4) Установка Docker Engine + Compose plugin
### 4.1 Вариант A: вручную командами
```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

### 4.2 Вариант B: скриптом
```bash
cat > ~/install_docker.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
echo "Docker installed. Re-login SSH or run: newgrp docker"
EOF
chmod +x ~/install_docker.sh
bash ~/install_docker.sh
```

После добавления в группу `docker` сделайте одно из двух:
1. Выйдите из SSH-сессии и зайдите снова.
2. Или выполните `newgrp docker` в текущем терминале.

Проверка:
```bash
docker --version
docker compose version
```

## 5) Подготовка переменных окружения
```bash
cp install_bundle/.env.example .env
nano .env
```

Минимальные обязательные параметры:
```dotenv
TELEGRAM_API_ID=...
TELEGRAM_API_HASH=...
TELEGRAM_BOT_TOKEN=...
ALERT_CHAT_ID=...
POSTGRES_DB=...
POSTGRES_USER=...
POSTGRES_PASSWORD=...
```

## 6) Первый запуск (без `telethon_worker`)
```bash
mkdir -p media
docker compose up -d --build db web bot_poller
docker compose exec -T web python manage.py migrate
```

## 7) Создание суперпользователя Django
```bash
docker compose exec web python manage.py createsuperuser
```

## 8) Авторизация Telegram-сессии в вебе
1. Откройте: `http://<IP-СЕРВЕРА>:8000/telegram/auth/method/`
2. Войдите под superuser.
3. Пройдите авторизацию Telegram по коду из SMS/Telegram.
4. Убедитесь, что сессия стала `authorized`.

## 9) Запуск парсера
```bash
docker compose up -d telethon_worker
```

## 10) Проверка состояния
```bash
docker compose ps
docker compose logs -f telethon_worker
docker compose logs -f bot_poller
```

## Автозапуск при старте Ubuntu
### Вариант A: через `nano` (пошагово)
1. Откройте файл службы:
```bash
sudo nano /etc/systemd/system/dozor.service
```
2. Вставьте текст:
```ini
[Unit]
Description=DoZoRProject (docker compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=YOUR_LINUX_USER
WorkingDirectory=/home/YOUR_LINUX_USER/projects/DoZoRProject
RemainAfterExit=yes
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```
3. Замените `YOUR_LINUX_USER` на пользователя из `whoami`.
4. Сохраните: `Ctrl + O` -> `Enter` -> `Ctrl + X`.
5. Включите службу:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dozor.service
systemctl status dozor.service --no-pager
```

### Вариант B: скриптом (копировать и вставить)
```bash
cd ~/projects/DoZoRProject
USERNAME="$(whoami)"
sudo tee /etc/systemd/system/dozor.service >/dev/null <<EOF
[Unit]
Description=DoZoRProject (docker compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${USERNAME}
WorkingDirectory=/home/${USERNAME}/projects/DoZoRProject
RemainAfterExit=yes
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now dozor.service
systemctl status dozor.service --no-pager
docker compose ps
```

Проверка после перезагрузки:
```bash
sudo reboot
```
После входа:
```bash
cd ~/projects/DoZoRProject
docker compose ps
```

Если не запустилось:
```bash
journalctl -u dozor.service -n 100 --no-pager
systemctl status docker --no-pager
```

## Автообновление каждые 30 минут
### 1) Создать скрипт обновления
```bash
sudo tee /usr/local/bin/dozor-update.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${HOME}/projects/DoZoRProject"
LOG_FILE="/var/log/dozor-update.log"

exec >> "$LOG_FILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] update start"

cd "$PROJECT_DIR"
git fetch origin master
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/master)"

if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] no changes"
  exit 0
fi

git reset --hard origin/master
docker compose up -d --build
docker compose exec -T web python manage.py migrate
echo "[$(date '+%Y-%m-%d %H:%M:%S')] update done: $LOCAL_SHA -> $REMOTE_SHA"
EOF
sudo chmod +x /usr/local/bin/dozor-update.sh
```

Скрипт использует домашний каталог текущего пользователя (`${HOME}`).

### 2) Создать systemd service для обновления
Вариант A (через `nano`):
```bash
sudo nano /etc/systemd/system/dozor-update.service
```
Вставьте:
```ini
[Unit]
Description=DoZoRProject update from GitHub
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=YOUR_LINUX_USER
ExecStart=/usr/local/bin/dozor-update.sh
```
Сохраните: `Ctrl + O` -> `Enter` -> `Ctrl + X`.

Вариант B (скриптом):
```bash
CURRENT_USER="$USER"
sudo tee /etc/systemd/system/dozor-update.service >/dev/null <<EOF
[Unit]
Description=DoZoRProject update from GitHub
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${CURRENT_USER}
ExecStart=/usr/local/bin/dozor-update.sh
EOF
```

### 3) Создать systemd timer
Вариант A (через `nano`):
```bash
sudo nano /etc/systemd/system/dozor-update.timer
```
Вставьте:
```ini
[Unit]
Description=Run DoZoRProject update periodically

[Timer]
OnBootSec=10min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
```
Сохраните: `Ctrl + O` -> `Enter` -> `Ctrl + X`.

Вариант B (скриптом):
```bash
sudo tee /etc/systemd/system/dozor-update.timer >/dev/null <<'EOF'
[Unit]
Description=Run DoZoRProject update periodically

[Timer]
OnBootSec=10min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

### 4) Включить автообновление
Вариант A (по командам):
```bash
sudo systemctl daemon-reload
sudo touch /var/log/dozor-update.log
sudo chmod 666 /var/log/dozor-update.log
sudo systemctl enable --now dozor-update.timer
systemctl list-timers --all | grep dozor-update
```

Вариант B (скриптом):
```bash
cat > ~/enable_dozor_autoupdate.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo systemctl daemon-reload
sudo touch /var/log/dozor-update.log
sudo chmod 666 /var/log/dozor-update.log
sudo systemctl enable --now dozor-update.timer
systemctl list-timers --all | grep dozor-update || true
echo "Auto-update timer enabled"
EOF
chmod +x ~/enable_dozor_autoupdate.sh
bash ~/enable_dozor_autoupdate.sh
```

Важно: автообновление делает `git reset --hard origin/master`, то есть локальные изменения в папке проекта будут удаляться.

### 5) Проверка автообновления
```bash
sudo systemctl start dozor-update.service
tail -n 50 /var/log/dozor-update.log
```

## Обновление до свежего `master`
```bash
cd ~/projects/DoZoRProject
git fetch origin master
git reset --hard origin/master
docker compose up -d --build
docker compose exec -T web python manage.py migrate
```

## Полезные страницы
- `http://<IP-СЕРВЕРА>:8000/telegram/auth/method/`
- `http://<IP-СЕРВЕРА>:8000/telegram/filters/`
- `http://<IP-СЕРВЕРА>:8000/telegram/monitoring/`
- `http://<IP-СЕРВЕРА>:8000/telegram/search/`
