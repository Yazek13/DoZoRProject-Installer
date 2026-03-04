# DoZoRProject Installer

Удобный репозиторий для установки и первичного запуска `DoZoRProject` на чистой Ubuntu.

## Что делает installer
- Устанавливает базовые пакеты и Docker.
- Помогает настроить SSH deploy key для приватного репозитория `Yazek13/DoZoRProject`.
- Клонирует проект в `~/projects/DoZoRProject`.
- Поднимает Docker-стек и применяет миграции.
- Настраивает автозапуск (`dozor.service`) и автообновление таймером (`dozor-update.timer`).

## Быстрый старт (рекомендуется)

### 1. Подготовка сервера
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

### 3. Запустить установку
```bash
sudo bash setup_ubuntu.sh
```

Скрипт попросит:
1. Скопировать публичный deploy key.
2. Добавить его в GitHub:
   1. `Yazek13/DoZoRProject -> Settings -> Deploy keys`
   2. `Add deploy key`
   3. Вставить ключ
   4. `Allow write access` оставить OFF
3. Нажать Enter и продолжить установку.

## Что сделать после установки

### 1. Создать Django superuser
```bash
cd ~/projects/DoZoRProject
docker compose exec web python manage.py createsuperuser
```

### 2. Авторизовать Telegram-сессию в вебе
Откройте:
- `http://<SERVER_IP>:18000/telegram/auth/method/`

Затем:
1. Войдите под superuser.
2. Пройдите авторизацию Telegram.
3. Убедитесь, что сессия стала `authorized`.

### 3. Запустить/перезапустить worker после авторизации
```bash
cd ~/projects/DoZoRProject
docker compose up -d telethon_worker
```

## Обязательные переменные в `.env`
Файл: `~/projects/DoZoRProject/.env`

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

## Полезные URL
- Главная: `http://<SERVER_IP>:18000/telegram/auth/method/`
- Фильтры: `http://<SERVER_IP>:18000/telegram/filters/`
- Мониторинг: `http://<SERVER_IP>:18000/telegram/monitoring/`
- Поиск: `http://<SERVER_IP>:18000/telegram/search/`

## Проверка состояния
```bash
cd ~/projects/DoZoRProject
docker compose ps
docker compose logs -f web
docker compose logs -f telethon_worker
docker compose logs -f bot_poller
```

## Автообновление
Installer включает:
- `dozor-update.service`
- `dozor-update.timer` (каждые 15 минут)

Проверка:
```bash
sudo systemctl status dozor-update.timer
sudo systemctl status dozor-update.service
```

Ручной запуск обновления:
```bash
sudo systemctl start dozor-update.service
```

Логи обновлений:
```bash
journalctl -u dozor-update.service -n 100 --no-pager
```

## Частые проблемы

### 1. `Unit dozor-update.service not found`
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dozor-update.timer
```

### 2. `port is already allocated` (PostgreSQL)
Проект использует host-порт `15432` для `db`. Если конфликт остался:
```bash
cd ~/projects/DoZoRProject
docker compose down
docker compose up -d --build
```

### 3. `telethon_worker` падает после старта
Это нормально, если Telegram-сессия еще не авторизована. Сначала авторизуйте сессию в вебе, потом:
```bash
docker compose up -d telethon_worker
```

## Ручное обновление проекта
```bash
cd ~/projects/DoZoRProject
git pull --ff-only origin master
docker compose up -d --build
docker compose exec -T web python manage.py migrate
```

## Лицензия
Проект и installer используются в рамках репозитория владельца.
