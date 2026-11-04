#!/bin/bash
#Скрипт проверяет shop
WARNING=1
CRITICAL=10
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
#Проверяем наличие конфига и логов
if [ ! -f "$config" ]; then
  echo "CRITICAL: нет файла $config"
  exit 2
fi
if [ ! -f "$log" ]; then
  echo "CRITICAL: нет файла $log"
  exit 2
fi
#Считаем ошибки в логе и выводим статус
errors=$(cat "$log" | grep "ERROR" | wc -l)
if [ "$errors" -ge "$CRITICAL" ]; then
  echo "CRITICAL: ошибок в логе: $errors"
  exit 2
elif [ "$errors" -ge "$WARNING" ]; then
  echo "WARNING: ошибок в логе: $errors"
  exit 1
else
  echo "OK: ошибок в логе: $errors"
  exit 0
fi
