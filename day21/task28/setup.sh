#!/bin/bash
# Задача 28: тестовые папки сервиса shop для ручных запусков check_shop.sh.
# Запуск:
#   bash setup.sh
# Создаёт папку ~/task28 с пятью «копиями» shop. Повторный запуск возвращает всё к началу.

base="$HOME/task28"
rm -rf "$base"

# make_shop папка число_ошибок есть_config есть_лог
make_shop() {
    local dir="$base/$1"
    mkdir -p "$dir"
    if [ "$3" == "yes" ]; then
        printf 'port: 8081\ndb_host: localhost\n' > "$dir/config.yaml"
    fi
    if [ "$4" == "yes" ]; then
        mkdir -p "$dir/logs"
        local log="$dir/logs/app.log"
        : > "$log"
        for i in 1 2 3 4 5; do
            echo "2026-11-04 10:00:0$i INFO заказ #$i принят" >> "$log"
        done
        echo "2026-11-04 10:00:30 WARN медленный ответ базы: 2.1 с" >> "$log"
        for i in $(seq 1 "$2"); do
            echo "2026-11-04 10:01:00 ERROR оплата заказа #$((100 + i)) не прошла" >> "$log"
        done
        echo "2026-11-04 10:02:00 INFO заказ #6 принят" >> "$log"
    fi
}

make_shop "shop"        3  yes yes   # 3 ошибки в логе
make_shop "shop-ok"     0  yes yes   # ошибок нет
make_shop "shop-broken" 2  no  yes   # нет config.yaml
make_shop "shop-new"    0  yes no    # нет папки logs и лога
make_shop "shop old"    12 yes yes   # пробел в имени папки, 12 ошибок

echo "Готово: тестовые папки в $base"
ls -1 "$base"
