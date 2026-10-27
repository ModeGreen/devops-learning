#!/bin/bash
# Задача 22: создаёт папку shop/ рядом со скриптом и запускает 4 процесса сервиса shop.
# Запуск:
#   bash setup.sh        — (пере)создать shop/ и запустить процессы заново
#   bash setup.sh stop   — остановить все процессы shop (в конце задачи)

cd "$(dirname "$0")" || exit 1
dir=$(pwd)

# остановить процессы shop, оставшиеся от прошлого запуска (только из этой папки)
stop_all() {
    pkill -9 -f "$dir/shop/bin/" 2>/dev/null
    sleep 1
}

if [ "$1" == "stop" ]; then
    stop_all
    echo "Процессы shop остановлены."
    exit 0
fi

stop_all
rm -rf shop
mkdir -p shop/bin shop/logs

# --- shop-web: веб-часть магазина, работает нормально ---
cat > shop/bin/shop-web.sh <<'END'
#!/bin/bash
# Веб-часть магазина. На TERM — аккуратно завершается.
log="$(dirname "$0")/../logs/web.log"
trap 'echo "web: получен TERM, соединения закрыты, остановлен" >> "$log"; exit 0' TERM
echo "web: запущен, слушаю порт 8080" >> "$log"
while true; do sleep 1; done
END

# --- shop-cache: кеш товаров в памяти, работает нормально (просто много памяти) ---
cat > shop/bin/shop-cache.py <<'END'
# Кеш товаров: держит в памяти ~300 МБ. На TERM — аккуратно завершается.
import signal, sys, time
from pathlib import Path

log = Path(__file__).parent.parent / "logs" / "cache.log"

def on_term(signum, frame):
    with open(log, "a") as f:
        f.write("cache: получен TERM, кеш сброшен на диск, остановлен\n")
    sys.exit(0)

signal.signal(signal.SIGTERM, on_term)
data = b"x" * (300 * 1024 * 1024)
with open(log, "a") as f:
    f.write("cache: загружено 300 МБ товаров\n")
while True:
    time.sleep(1)
END

# --- shop-worker: обработчик заказов, ушёл в бесконечный цикл и ест процессор ---
cat > shop/bin/shop-worker.sh <<'END'
#!/bin/bash
# Обработчик заказов. Завис в цикле и грузит процессор на 100%.
# На TERM — сохраняет очередь заказов и завершается.
log="$(dirname "$0")/../logs/worker.log"
trap 'echo "worker: получен TERM, очередь заказов сохранена (12 шт.), остановлен" >> "$log"; exit 0' TERM
echo "worker: запущен, обрабатываю очередь" >> "$log"
# учебный предохранитель: через 60 минут воркер останавливается сам
while [ "$SECONDS" -lt 3600 ]; do :; done
echo "worker: учебный лимит 60 минут, остановлен сам" >> "$log"
END

# --- shop-mailer: рассыльщик писем, завис и не реагирует на TERM ---
cat > shop/bin/shop-mailer.sh <<'END'
#!/bin/bash
# Рассыльщик писем. Завис на подключении к почтовому серверу и игнорирует TERM.
log="$(dirname "$0")/../logs/mailer.log"
trap 'echo "mailer: получен TERM — завис, не реагирую" >> "$log"' TERM
echo "mailer: подключаюсь к smtp.internal:25…" >> "$log"
while true; do sleep 1; done
END

chmod 755 shop/bin/*.sh

# запуск в фоне; nohup — чтобы процессы не завершились вместе с этим скриптом
nohup bash "$dir/shop/bin/shop-web.sh"     > /dev/null 2>&1 &
nohup python3 "$dir/shop/bin/shop-cache.py" > /dev/null 2>&1 &
nohup bash "$dir/shop/bin/shop-worker.sh"  > /dev/null 2>&1 &
nohup bash "$dir/shop/bin/shop-mailer.sh"  > /dev/null 2>&1 &
sleep 1

echo "Готово. Запущено 4 процесса сервиса shop. Логи — в shop/logs/."
echo "В конце задачи: bash setup.sh stop"
