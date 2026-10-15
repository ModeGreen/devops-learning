#!/bin/bash
# Задача 11: создаёт «бардак» в папке incoming/ для тренировки.
# Запуск: bash setup.sh   (можно запускать повторно — всё начнётся с нуля)

cd "$(dirname "$0")" || exit 1

rm -rf incoming server
mkdir -p incoming/old_configs incoming/empty

echo "2026-10-15 10:00:01 INFO app started"      > incoming/app.log
echo "2026-10-14 23:59:59 INFO app stopped"      > incoming/app.log.1
echo "2026-10-13 23:59:59 INFO app stopped"      > incoming/app.log.2
echo "2026-10-15 10:05:42 ERROR db timeout"      > incoming/error.log

echo "server { listen 80; }"                     > incoming/nginx.conf
echo "DB_HOST=localhost"                         > incoming/app.conf

echo "old config 1"                              > incoming/old_configs/old1.conf
echo "old config 2"                              > incoming/old_configs/old2.conf

for n in 1 2 3 10; do
    echo "cache $n"                              > "incoming/cache_$n.tmp"
done
echo "НЕ УДАЛЯТЬ: незавершённая выгрузка"        > incoming/important.tmp

echo "Отчёт за неделю: всё стабильно"            > "incoming/report final.txt"

echo "Готово. Содержимое incoming/:"
ls -la incoming
