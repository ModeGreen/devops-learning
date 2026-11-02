#!/bin/bash
# Задача 26: убрать учебные службы shop-web и shop-mailer и все их файлы.
# Запускать только после того, как задача засчитана:
#   bash cleanup.sh

sudo systemctl disable --now -q shop-web shop-mailer 2>/dev/null
sudo rm -f /etc/systemd/system/shop-web.service /etc/systemd/system/shop-mailer.service
sudo rm -f /usr/local/bin/shop-web /usr/local/bin/shop-mailer
sudo rm -f /etc/shop/mailer.conf /var/tmp/task26.setup
sudo rmdir /etc/shop 2>/dev/null
sudo systemctl daemon-reload
sudo systemctl reset-failed shop-web shop-mailer 2>/dev/null
echo "Службы shop-web и shop-mailer убраны."
