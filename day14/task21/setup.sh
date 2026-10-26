#!/bin/bash
# Задача 21: создаёт папку shop/ рядом со скриптом — логи, конфиги и проверка сервиса shop.
# Запуск: bash setup.sh   (можно запускать повторно — всё создаётся заново)

cd "$(dirname "$0")" || exit 1
# в shop/secret нет прав (chmod 000) — вернуть их, иначе rm не сможет удалить папку
if [ -d shop ]; then chmod -R u+rwx shop; fi
rm -rf shop
mkdir -p shop/config shop/logs shop/bin shop/reports shop/secret

# --- config ---
cat > shop/config/app.conf <<'END'
port = 8080
workers = 4
END

cat > shop/config/nginx.conf <<'END'
server {
    listen 80;
    server_name shop.example.com;
}
END

cat > shop/secret/db.conf <<'END'
password = change-me
END

# --- проверка сервиса: OK — в обычный вывод, FAIL — в поток ошибок ---
cat > shop/bin/healthcheck.sh <<'END'
#!/bin/bash
# Проверка сервиса shop. OK пишет в stdout, FAIL — в stderr.
echo "OK   disk /srv/shop 41%"
echo "OK   service shop running"
echo "FAIL db.internal:5432 connection refused" >&2
echo "OK   port 8080 open"
echo "FAIL certificate shop.example.com expires in 3 days" >&2
END
chmod 755 shop/bin/healthcheck.sh

# --- журнал дежурств ---
cat > shop/reports/duty.log <<'END'
2026-10-23 смену принял, всё спокойно
2026-10-24 перезапуск shop после обновления
2026-10-25 почищены старые логи
END

# --- app.log: лог приложения ---
for i in $(seq 1 120); do
    t=$(printf "2026-10-26 09:%02d:%02d" $(( i / 60 )) $(( i % 60 )))
    if [ "$i" -eq 77 ]; then
        echo "$t ERROR disk /srv/shop/uploads: no space left"
    elif [ $(( i % 17 )) -eq 0 ]; then
        echo "$t ERROR order id=$i db timeout"
    elif [ $(( i % 29 )) -eq 0 ]; then
        echo "$t ERROR payment gateway: connection refused"
    elif [ $(( i % 31 )) -eq 0 ]; then
        echo "$t WARN order id=$i slow response"
    else
        echo "$t INFO order id=$i ok"
    fi
done > shop/logs/app.log

# --- access.log: журнал запросов веб-сервера ---
ips=()
add() { for _ in $(seq 1 "$2"); do ips+=("$1"); done; }
add 10.0.0.7 57
add 192.168.1.20 43
add 10.0.0.3 38
add 172.16.0.5 21
add 10.0.0.12 12
add 203.0.113.9 9
n=${#ips[@]}
urls=(/api/orders /api/cart / /login /api/products /api/orders)
for i in $(seq 0 $(( n - 1 ))); do
    ip=${ips[$(( i * 7919 % n ))]}
    url=${urls[$(( i % 6 ))]}
    if [ $(( i % 37 )) -eq 0 ]; then code=500
    elif [ $(( i % 13 )) -eq 0 ]; then code=404
    else code=200; fi
    printf '%s - - [26/Oct/2026:10:%02d:%02d +0300] "GET %s HTTP/1.1" %s %s\n' \
        "$ip" $(( i / 60 )) $(( i % 60 )) "$url" "$code" $(( 200 + i * 37 % 900 ))
done > shop/logs/access.log

chmod 000 shop/secret

echo "Готово. Посмотри, что создалось: find shop"
