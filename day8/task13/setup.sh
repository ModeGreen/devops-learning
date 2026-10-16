#!/bin/bash
# Задача 13: создаёт config.yaml — конфиг сервиса с ошибками.
# Запуск: bash setup.sh
# Повторный запуск НЕ перезапишет твои правки. Начать заново: bash setup.sh --force

cd "$(dirname "$0")" || exit 1

if [ -f config.yaml ] && [ "$1" != "--force" ]; then
    echo "config.yaml уже есть — не перезаписываю (твои правки пропали бы)."
    echo "Начать заново: bash setup.sh --force"
    exit 1
fi

cat > config.yaml <<'CONF'
# orders-api — конфиг сервиса
# Задача 13: править только в nano!

service:
  name: orders-api
  version: 2.4.1
  debug: true
  workers: 4

database:
  host: old-db.local
  port: 5432
  name: orders
  user: orders_app
  pool_size: 10

replica:
  host: old-db.local
  port: 5433

# --- BEGIN legacy ---
legacy_mode: true
legacy_endpoint: http://old-db.local:9000/v1
# --- END legacy ---

cache:
  host: redis.internal
  port: 6379
  ttl: 300

logging:
  level: info
  file: /var/log/orders-api/app.log
  max_size_mb: 100

server:
  host: 0.0.0.0
  port: 8008
  timeout: 30

backup:
  source: old-db.local
  target: s3://orders-backup
  schedule: "0 3 * * *"

migrations:
  db: old-db.local
  dir: /opt/orders-api/migrations

metrics:
  enabled: true
  path: /metrics
  port: 9100
CONF

echo "Готово: config.yaml, строк: $(wc -l < config.yaml)"
