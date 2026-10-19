#!/bin/bash
# Задача 15: создаёт папку ~/shop с неправильными правами.
# Повторный запуск ничего не трогает. Начать заново: bash setup.sh --force
set -e
APP="$HOME/shop"

if [ -d "$APP" ] && [ "$1" != "--force" ]; then
    echo "$APP уже есть — оставляю как есть. Начать заново: bash setup.sh --force"
    exit 0
fi

if [ -d "$APP" ]; then
    chmod -R u+rwx "$APP"
    rm -rf "$APP"
fi

mkdir -p "$APP/keys"

cat > "$APP/deploy.sh" <<'END'
#!/bin/bash
echo "Деплой shop: копирую файлы... готово"
END

cat > "$APP/.env" <<'END'
DB_PASSWORD=super-secret-123
END

cat > "$APP/keys/id_deploy" <<'END'
-----BEGIN OPENSSH PRIVATE KEY-----
учебный ключ, не настоящий
-----END OPENSSH PRIVATE KEY-----
END

# Неправильные права — их и надо исправить
chmod 644 "$APP/deploy.sh" "$APP/.env" "$APP/keys/id_deploy"
chmod 755 "$APP/keys"

echo "Готово: создана папка $APP"
