#!/bin/bash
# Задача 12: создаёт файлы для тренировки просмотра.
# Запуск: bash setup.sh   (можно запускать повторно — всё создаётся заново)

cd "$(dirname "$0")" || exit 1
rm -f app.log nginx.conf old.log.gz live.log

# app.log — 1000 строк «лога приложения»
for i in $(seq 1 1000); do
    h=$(( 10 + i / 3600 )); m=$(( i / 60 % 60 )); s=$(( i % 60 ))
    t=$(printf "2026-10-15 %02d:%02d:%02d" "$h" "$m" "$s")
    if [ "$i" -eq 737 ]; then
        echo "$t PANIC worker-3 crashed: out of memory"
    elif [ $(( i % 97 )) -eq 0 ]; then
        echo "$t ERROR request id=$i db timeout"
    else
        echo "$t INFO request id=$i ok"
    fi
done > app.log

# nginx.conf — с «невидимыми» проблемами
printf 'server {\n'                      >  nginx.conf
printf '    listen 80;\n'                >> nginx.conf
printf '    server_name example.com;\n'  >> nginx.conf
printf '    root /var/www/html;\r\n'     >> nginx.conf
printf '\tindex index.html;   \n'        >> nginx.conf
printf '}\n'                             >> nginx.conf

# old.log.gz — вчерашний лог, сжатый (так делает logrotate)
printf '2026-10-14 23:59:01 INFO rotate start\n2026-10-14 23:59:02 INFO 15230 requests today\n2026-10-14 23:59:03 INFO rotate done\n' | gzip > old.log.gz

echo "Готово:"
ls -l app.log nginx.conf old.log.gz
