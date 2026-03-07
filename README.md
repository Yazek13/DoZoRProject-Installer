# DoZoRProject Installer

Installer для чистой Ubuntu, который разбивает подготовку сервера на два шага:
1. `bootstrap_ubuntu.sh` — системные зависимости и Docker
2. `setup_ubuntu.sh` — deploy key, clone проекта, `.env`, Docker-стек, systemd, автообновление

## Что делает installer
- ставит базовые пакеты и Docker через `bootstrap_ubuntu.sh`
- помогает настроить SSH deploy key для приватного репозитория `Yazek13/DoZoRProject`
- клонирует проект в `~/DoZoR`
- поднимает Docker-стек и применяет миграции
- настраивает `dozor.service`
- настраивает `dozor-update.service` и `dozor-update.timer`
- позволяет выбрать ветку `dev` или `master`

## Быстрый старт

### 1. Подготовить сервер
```bash
sudo apt update
sudo apt install -y git
```

### 2. Клонировать installer
```bash
cd ~
git clone https://github.com/Yazek13/DoZoRProject-Installer.git
cd DoZoRProject-Installer
```

### 3. Установить системные зависимости
```bash
sudo bash bootstrap_ubuntu.sh
```

Что ставит `bootstrap_ubuntu.sh`:
- `git`
- `curl`
- `ca-certificates`
- `gnupg`
- `lsb-release`
- `openssh-client`
- `nano`
- Docker Engine
- Docker Compose plugin

### 4. Установить проект
```bash
sudo bash setup_ubuntu.sh
```

Или сразу выбрать ветку:
```bash
sudo bash setup_ubuntu.sh dev
sudo bash setup_ubuntu.sh master
```

Что делает `setup_ubuntu.sh`:
1. Проверяет, что `git`, `curl`, `docker` и `docker compose` уже установлены
2. Генерирует deploy key
3. Ждёт, пока вы добавите deploy key в GitHub
4. Клонирует репозиторий в `~/DoZoR`
5. Создаёт `.env` из `install_bundle/.env.example`
6. Поднимает Docker-стек
7. Выполняет миграции
8. Настраивает `dozor.service`
9. Настраивает `dozor-update.service` и `dozor-update.timer`

Если не хватает зависимостей, `setup_ubuntu.sh` остановится и попросит сначала запустить `bootstrap_ubuntu.sh`.

## Что сделать после установки

### Создать superuser
```bash
cd ~/DoZoR
docker compose exec web python manage.py createsuperuser
```

### Авторизовать Telegram-сессию
Открыть:
- `http://<SERVER_IP>:18000/telegram/auth/method/`

Дальше:
1. Войти под superuser
2. Пройти авторизацию Telegram
3. Убедиться, что сессия стала `authorized`

### Запустить worker
```bash
cd ~/DoZoR
docker compose up -d telethon_worker
```

## Обязательные переменные в `.env`

Файл:
- `~/DoZoR/.env`

Минимум:
```dotenv
TELEGRAM_API_ID=...
TELEGRAM_API_HASH=...
TELEGRAM_BOT_TOKEN=...
ALERT_CHAT_ID=...
POSTGRES_DB=...
POSTGRES_USER=...
POSTGRES_PASSWORD=...
```

## Проверка состояния
```bash
cd ~/DoZoR
docker compose ps
docker compose logs -f web
docker compose logs -f telethon_worker
docker compose logs -f bot_poller
```

## Автообновление

После установки installer настраивает:
- `dozor-update.service`
- `dozor-update.timer`
- выбранную ветку автообновления: `dev` или `master`

Проверить:
```bash
sudo systemctl status dozor-update.timer
sudo systemctl status dozor-update.service
```

Запустить вручную:
```bash
sudo systemctl start dozor-update.service
```

Логи:
```bash
journalctl -u dozor-update.service -n 100 --no-pager
tail -n 100 /var/log/dozor-update.log
```

## Переключить существующий сервер на `dev` или `master`

### Рекомендуемый способ
Если сервер уже обновлён до свежего проекта:
```bash
cd ~/DoZoR
sudo bash scripts/install_auto_update.sh
```

Скрипт сам предложит выбрать `dev` или `master`.

### Явно выбрать ветку
```bash
cd ~/DoZoR
sudo bash scripts/install_auto_update.sh dev ~/DoZoR $USER
sudo bash scripts/install_auto_update.sh master ~/DoZoR $USER
```

### Ручное переключение на `dev`
```bash
cd ~/DoZoR
git fetch origin dev
git checkout dev || git checkout -b dev --track origin/dev
git reset --hard origin/dev
sudo systemctl daemon-reload
sudo bash scripts/install_auto_update.sh dev ~/DoZoR $USER
sudo systemctl restart dozor-update.timer
sudo systemctl start dozor-update.service
```

### Ручное переключение на `master`
```bash
cd ~/DoZoR
git fetch origin master
git checkout master || git checkout -b master --track origin/master
git reset --hard origin/master
sudo systemctl daemon-reload
sudo bash scripts/install_auto_update.sh master ~/DoZoR $USER
sudo systemctl restart dozor-update.timer
sudo systemctl start dozor-update.service
```

## Полезные URL
- Главная: `http://<SERVER_IP>:18000/telegram/auth/method/`
- Фильтры: `http://<SERVER_IP>:18000/telegram/filters/`
- Мониторинг: `http://<SERVER_IP>:18000/telegram/monitoring/`
- Поиск: `http://<SERVER_IP>:18000/telegram/search/`

## Частые проблемы

### `Unit dozor-update.service not found`
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dozor-update.timer
```

### `port is already allocated`
```bash
cd ~/DoZoR
docker compose down
docker compose up -d --build
```

### `telethon_worker` падает после старта
Это нормально, если Telegram-сессия ещё не авторизована.
Сначала авторизуйте сессию в вебе, потом:
```bash
docker compose up -d telethon_worker
```

## Ручное обновление проекта
```bash
cd ~/DoZoR
git pull --ff-only origin <dev-or-master>
docker compose up -d --build
docker compose exec -T web python manage.py migrate
```

## Лицензия
Проект и installer используются в рамках репозитория владельца.
