#!/bin/bash
#Скрипт проверяет shop
host=$(hostname)
echo "Проверка shop на сервере $host"
if [ "$#" -ne 1 ]; then
echo "ОШИБКА: нужeн 1 аргумент: папка. Получено: $#" >&2
exit 3
fi
dir="$1"
if [ ! -d "$dir" ]; then
echo "ОШИБКА: нет папки $dir" >&2
exit 3
fi
echo "Папка: $dir"
config="$dir/config.yaml"
log="$dir/logs/app.log"
if [ ! -f "$config" ]; then
echo "CRITICAL: нет файла $config"
exit 2
fi
if [ ! -f "$log" ]; then
echo "CRITICAL: нет файла $log"
exit 2
fi
