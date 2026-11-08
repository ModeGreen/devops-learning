#!/bin/bash
#Ждёт файл флажок shop.ready
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