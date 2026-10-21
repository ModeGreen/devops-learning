#!/bin/bash
# Задача 17: создаёт /srv/shop — папку сервиса shop (права уже как после Задачи 15).
# Повторный запуск ничего не трогает. Начать заново: bash setup.sh --force
set -e
APP=/srv/shop
ME=$(whoami)

if [ "$ME" == "root" ]; then
    echo "Запусти без sudo: bash setup.sh (sudo скрипт попросит сам)"
    exit 1
fi

if [ -d "$APP" ] && [ "$1" != "--force" ]; then
    echo "$APP уже есть — оставляю как есть. Начать заново: bash setup.sh --force"
    exit 0
fi

echo "Создаю $APP. Нужен sudo — введи пароль своего пользователя Ubuntu (символы не видны, это нормально)."
sudo rm -rf "$APP"
sudo mkdir -p "$APP"
sudo chown "$ME:$ME" "$APP"
chmod 755 "$APP"

cd "$APP"
mkdir keys logs

cat > deploy.sh <<'END'
#!/bin/bash
echo "Деплой shop: копирую файлы... готово"
END

cat > config.yaml <<'END'
service:
  name: shop
  port: 8080
database:
  host: db.internal
  name: shop
END

cat > .env <<'END'
DB_PASSWORD=super-secret-123
END

cat > keys/id_deploy <<'END'
-----BEGIN OPENSSH PRIVATE KEY-----
учебный ключ, не настоящий
-----END OPENSSH PRIVATE KEY-----
END

echo "2026-10-21 10:00:00 shop started" > logs/app.log

chmod 755 deploy.sh logs
chmod 644 config.yaml logs/app.log
chmod 600 .env keys/id_deploy
chmod 700 keys

echo "Готово. Посмотри: ls -la $APP"
