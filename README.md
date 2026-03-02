# DoZoRProject Installer

Подробная инструкция для развёртывания `DoZoRProject` на новой Ubuntu (без установочных скриптов).

## Важно
- Сначала запускаются `db`, `web`, `bot_poller`.
- Затем выполняется авторизация Telegram-сессии через веб.
- Только после этого запускается `telethon_worker`.

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

Настроить SSH-клиент:
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

## 3) Клонирование проекта
```bash
mkdir -p ~/projects
cd ~/projects
git clone git@github.com:Yazek13/DoZoRProject.git
cd DoZoRProject
```

## 4) Установка Docker Engine + Compose plugin
```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

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
Создать systemd unit:
```bash
CURRENT_USER="$USER"
sudo tee /etc/systemd/system/dozor.service >/dev/null <<EOF
[Unit]
Description=DoZoRProject (docker compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${CURRENT_USER}
WorkingDirectory=/home/${CURRENT_USER}/projects/DoZoRProject
RemainAfterExit=yes
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
```

Включить:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dozor.service
systemctl status dozor.service --no-pager
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
