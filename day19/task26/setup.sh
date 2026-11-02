#!/bin/bash
# Задача 26: «коллега» переводит shop на systemd — ставит службы shop-web и shop-mailer.
# Запуск (спросит пароль sudo):
#   bash setup.sh
# Повторный запуск возвращает всё к началу задачи.

if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    echo "В этой системе не работает systemd (PID 1 — $(ps -p 1 -o comm=)). Напиши Claude — включим."
    exit 1
fi

echo "Коллега ставит службы shop-web и shop-mailer…"

# Программа службы shop-web: «принимает заказы» — раз в 10 секунд пишет строку.
sudo tee /usr/local/bin/shop-web >/dev/null <<'EOF'
#!/bin/bash
# Учебная служба из Задачи 26: «принимает заказы» — раз в 10 секунд пишет строку в журнал.
echo "shop-web запущен, принимаю заказы на порту 8081"
n=0
while true; do
    n=$((n + 1))
    echo "заказ #$n обработан"
    sleep 10
done
EOF

# Программа службы shop-mailer: без настройки smtp_host падает с кодом 1.
sudo tee /usr/local/bin/shop-mailer >/dev/null <<'EOF'
#!/bin/bash
# Учебная служба из Задачи 26: «отправляет письма». Без настройки smtp_host падает с кодом 1.
CONF=/etc/shop/mailer.conf
host=$(grep -s '^smtp_host=' "$CONF" | head -n 1 | cut -d= -f2)
if [ -z "$host" ]; then
    echo "ОШИБКА: нет строки smtp_host= в $CONF (пример строки: smtp_host=localhost)" >&2
    exit 1
fi
echo "shop-mailer запущен, почтовый сервер: $host"
while true; do
    echo "очередь писем пуста"
    sleep 30
done
EOF
sudo chmod 755 /usr/local/bin/shop-web /usr/local/bin/shop-mailer

sudo tee /etc/systemd/system/shop-web.service >/dev/null <<'EOF'
[Unit]
Description=Shop web

[Service]
ExecStart=/usr/local/bin/shop-web
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/shop-mailer.service >/dev/null <<'EOF'
[Unit]
Description=Shop mailer

[Service]
ExecStart=/usr/local/bin/shop-mailer

[Install]
WantedBy=multi-user.target
EOF

# Начальное состояние: конфига почты нет, у shop-web автозапуск выключен, у shop-mailer — включён.
sudo systemctl stop shop-web shop-mailer 2>/dev/null
sudo rm -f /etc/shop/mailer.conf
sudo rmdir /etc/shop 2>/dev/null
sudo systemctl daemon-reload
sudo systemctl disable -q shop-web 2>/dev/null
sudo systemctl enable -q shop-mailer 2>/dev/null
sudo systemctl reset-failed shop-web shop-mailer 2>/dev/null
sudo systemctl start shop-web shop-mailer
sleep 1
# Время установки — проверка смотрит журнал только после него.
date '+%Y-%m-%d %H:%M:%S' | sudo tee /var/tmp/task26.setup >/dev/null

echo
echo "Готово: службы shop-web и shop-mailer установлены. Дальше — Шаг 1."
