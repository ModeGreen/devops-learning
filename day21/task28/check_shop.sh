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
