#!/bin/bash
# Задача 24, шаг 5: «коллега» ставит на сервер файловый менеджер mc.
# Запуск (спросит пароль sudo):
#   bash setup.sh

echo "Коллега ставит mc (Midnight Commander)…"
sudo apt-get install -y --no-install-recommends mc || {
    echo "Не получилось поставить mc. Сначала: sudo apt update — и запусти setup.sh ещё раз."
    exit 1
}
echo
echo "Готово: mc установлен, его настройки — в /etc/mc:"
ls /etc/mc
