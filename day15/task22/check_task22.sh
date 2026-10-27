#!/bin/bash
# Проверка Задачи 22. Запуск из папки задачи:
#   bash check_task22.sh      — всё
#   bash check_task22.sh 3    — только шаг 3 (и так же 1…5)
# Проверяет ЖИВЫЕ процессы из shop/, которые запустил setup.sh, и логи в shop/logs/.
# Поэтому полную проверку запускай ДО `bash setup.sh stop`.

cd "$(dirname "$0")" || exit 1
here=$(pwd)
bin="$here/shop/bin"
STEP="${1:-all}"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

alive() { pgrep -f "$bin/$1" > /dev/null; }
in_log() { grep -q "$2" "$here/shop/logs/$1" 2>/dev/null; }

# web и cache должны работать: их трогать не нужно
others_alive() {
    local dead=""
    alive shop-web.sh   || dead="$dead shop-web.sh"
    alive shop-cache.py || dead="$dead shop-cache.py"
    if [ -z "$dead" ]; then
        ok "лишнего не задел: shop-web и shop-cache работают"
    else
        bad "остановлен лишний процесс:$dead — его трогать было не нужно. bash setup.sh и шаги 3–4 заново"
    fi
}

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

if [ ! -d "$here/shop/bin" ]; then
    echo "Нет папки shop/ — сначала: bash setup.sh"
    exit 1
fi

if run_step 1; then
    echo "Шаг 1. Найти процессы shop"
    live=$(pgrep -f "$bin/")
    f="$here/q1.sh"
    if [ -z "$live" ]; then
        bad "ни один процесс shop не запущен — bash setup.sh"
    elif [ ! -f "$f" ]; then
        bad "q1.sh — нет файла"
    else
        out=$(bash "$f" 2>&1)
        missing=""
        for pid in $live; do
            echo "$out" | grep -qw "$pid" || missing="$missing $pid"
        done
        n_live=$(echo "$live" | wc -l)
        n_out=$(echo "$out" | grep -c .)
        if [ -z "$out" ]; then
            bad "q1.sh ничего не нашёл (подсказка: у скрипта имя процесса — bash или python3, а не shop-…)"
        elif echo "$out" | grep -q 'grep'; then
            bad "q1.sh — в выводе есть строка самого grep (часть 2.2 урока)"
        elif [ -n "$missing" ]; then
            bad "q1.sh — нашлись не все процессы shop, нет PID:$missing"
        elif [ "$n_out" -ne "$n_live" ]; then
            bad "q1.sh — лишние строки: процессов shop $n_live, а строк в выводе $n_out"
        elif echo "$out" | grep -vq 'shop/bin'; then
            bad "q1.sh — PID есть, но не видно полной команды (какой флаг pgrep её печатает?)"
        else
            ok "q1.sh — все процессы shop ($n_live шт.): PID и полная команда, без лишних строк"
        fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. top"
    f="$here/answers.txt"
    if [ ! -f "$f" ]; then
        bad "answers.txt — нет файла"
    else
        cpu=$(grep '^cpu:' "$f")
        mem=$(grep '^mem:' "$f")
        if [ -z "$cpu" ]; then bad "answers.txt — нет строки cpu: …"
        elif echo "$cpu" | grep -q 'shop-worker\.sh'; then ok "cpu — верно"
        else bad "cpu — не тот процесс (в top: клавиша P, потом c)"; fi
        if [ -z "$mem" ]; then bad "answers.txt — нет строки mem: …"
        elif echo "$mem" | grep -q 'shop-cache\.py'; then ok "mem — верно"
        else bad "mem — не тот процесс (в top: клавиша M, потом c)"; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Остановить shop-worker"
    if alive shop-worker.sh; then
        bad "shop-worker ещё работает"
    elif in_log worker.log 'учебный лимит'; then
        bad "shop-worker остановился сам по учебному таймеру (60 минут) — bash setup.sh и шаги 3–4 заново"
    elif in_log worker.log 'получен TERM'; then
        ok "shop-worker остановлен обычным kill и успел сохранить очередь"
    else
        bad "shop-worker убит через kill -9 и не сохранил очередь — нужен обычный kill. bash setup.sh и шаги 3–4 заново"
    fi
    others_alive
fi

if run_step 4; then
    echo "Шаг 4. Остановить зависший shop-mailer"
    if alive shop-mailer.sh; then
        if in_log mailer.log 'получен TERM'; then
            bad "shop-mailer получил обычный kill, но всё ещё работает — что дальше? (часть 5.3)"
        else
            bad "shop-mailer ещё работает"
        fi
    elif in_log mailer.log 'получен TERM'; then
        ok "сначала обычный kill, и только потом kill -9 — shop-mailer остановлен"
    else
        bad "shop-mailer сразу убит через kill -9 — сначала обычный kill. bash setup.sh и шаги 3–4 заново"
    fi
    others_alive
fi

if run_step 5; then
    echo "Шаг 5. Git"
    for f in q1.sh answers.txt setup.sh check_task22.sh .gitignore; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f добавлен в Git"; else bad "$f не добавлен в Git"; fi
    done
    if git check-ignore -q shop/logs/web.log 2>/dev/null; then ok "shop/ не попадёт в Git (.gitignore)"
    else bad "shop/ не в .gitignore — сгенерированные файлы попадут в Git"; fi
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
