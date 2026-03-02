# DoZoRProject Installer

Запуск на чистой Ubuntu одной командой:

```
curl -fsSL https://raw.githubusercontent.com/Yazek13/DoZoRProject-Installer/master/setup_ubuntu.sh | sudo bash
```

Этот скрипт:
- ставит git/curl
- генерирует deploy key
- ждёт, пока ключ добавят в GitHub
- клонирует приватный DoZoRProject
- ставит Docker
- запускает сервисы и миграции

После установки:
1. Откройте `http://<server-ip>:8000/telegram/auth/method/`
2. Войдите в Django Admin (создайте superuser при необходимости)
3. Авторизуйте Telegram-сессию по коду
4. Затем запустите `telethon_worker`, если он не стартовал автоматически:
```bash
cd ~/projects/DoZoRProject
docker compose up -d telethon_worker
```
