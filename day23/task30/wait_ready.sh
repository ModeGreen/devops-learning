#!/bin/bash
#Ждёт файл флажок shop.ready
if [ $# -ne 2 ]; then
    echo "ОШИБКА: нужно 2 аргумента: файл и число попыток" >&2
    exit 2
fi
file=$1
max=$2
i=1
while [ "$i" -le "$max" ]; do
    if [ -f "$file" ]; then
        echo "Готово: $file есть, попытка $i из $max"
        exit 0
    else
        echo "Жду $file: попытка $i из $max"
        i=$((i + 1))
        sleep 1
    fi
done
echo "ОШИБКА: $file не появился за $max с" >&2
exit 1