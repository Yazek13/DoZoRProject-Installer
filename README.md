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
