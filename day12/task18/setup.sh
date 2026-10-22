#!/bin/bash
# Задача 18: создаёт папку shop/ рядом со скриптом — файлы сервиса shop для поиска.
# Запуск: bash setup.sh   (можно запускать повторно — всё создаётся заново)

cd "$(dirname "$0")" || exit 1
rm -rf shop
mkdir -p shop/config shop/logs shop/backups shop/src

# --- config ---
cat > shop/config/nginx.conf <<'END'
# nginx для сервиса shop
# собран 2026-10-01, менять через Git
server {
    listen 80; # пока только http, https — на этапе 2
    server_name shop.example.com;
# root /var/www/old;
    root /srv/shop/public;
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
    }
}
END

cat > shop/config/app.yaml <<'END'
# настройки сервиса shop
service:
  name: shop
  port: 8080
database:
  host: db.internal
  port: 5432
END

cat > shop/config/db.yaml <<'END'
host: db.internal
user: shop
password: change-me
END

# --- src ---
cat > shop/src/settings.py <<'END'
DB_HOST = "db.internal"
DEBUG = False
END

cat > shop/src/main.py <<'END'
print("shop started")
END

cat > shop/README.md <<'END'
Сервис shop. База данных — на отдельном сервере, адрес в настройках.
END

# --- logs ---
for i in $(seq 1 200); do
    h=$(( 10 + i / 60 )); m=$(( i % 60 ))
    t=$(printf "2026-10-22 %02d:%02d:00" "$h" "$m")
    if [ "$i" -eq 150 ]; then
        echo "$t Error payment gateway: connection refused"
    elif [ $(( i % 23 )) -eq 0 ]; then
        echo "$t ERROR order id=$i db timeout"
    elif [ $(( i % 41 )) -eq 0 ]; then
        echo "$t WARN order id=$i retry after error"
    else
        echo "$t INFO order id=$i ok"
    fi
done > shop/logs/app.log

echo "2026-10-19 12:00:00 INFO shop started"  > shop/logs/app.log.1
echo "2026-10-12 12:00:00 INFO shop started"  > shop/logs/app.log.2
echo "2026-10-02 12:00:00 INFO shop started"  > shop/logs/app.log.3
yes "2026-10-22 10:00:00 DEBUG worker heartbeat" | head -c 2M > shop/logs/worker.log

# --- backups (содержимое — нули, важен только размер) ---
head -c 3M /dev/zero > shop/backups/db-2026-10-01.sql.gz
head -c 3M /dev/zero > shop/backups/db-2026-10-20.sql.gz

# --- возраст файлов (дата изменения) ---
touch -d '3 days ago'  shop/logs/app.log.1
touch -d '10 days ago' shop/logs/app.log.2
touch -d '20 days ago' shop/logs/app.log.3
touch -d '21 days ago' shop/backups/db-2026-10-01.sql.gz
touch -d '2 days ago'  shop/backups/db-2026-10-20.sql.gz

echo "Готово. Посмотри, что создалось: find shop"
