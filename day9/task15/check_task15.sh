#!/bin/bash
# Проверка Задачи 15.
#   bash check_task15.sh 2   — только шаг 2 (так же 3, 4, 5)
#   bash check_task15.sh     — всё сразу
APP="$HOME/shop"
STEP="${1:-all}"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

# mode путь нужные_права
mode() {
    if [ ! -e "$1" ]; then bad "$1 не найден"; return; fi
    local got
    got=$(stat -c '%a' "$1")
    if [ "$got" == "$2" ]; then ok "$1: $got"; else bad "$1: сейчас $got, нужно $2"; fi
}

if [ ! -d "$APP" ]; then
    echo "❌ $APP не найден — сначала bash setup.sh"
    exit 1
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "2" ]; then
    echo "Шаг 2. deploy.sh"
    mode "$APP/deploy.sh" 755
    if "$APP/deploy.sh" >/dev/null 2>&1; then ok "deploy.sh запускается"; else bad "deploy.sh не запускается"; fi
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "3" ]; then
    echo "Шаг 3. .env"
    mode "$APP/.env" 600
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "4" ]; then
    echo "Шаг 4. keys"
    mode "$APP/keys" 700
    mode "$APP/keys/id_deploy" 600
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "5" ]; then
    echo "Шаг 5. solution.sh (запускать из папки задачи)"
    if [ ! -f solution.sh ]; then
        bad "solution.sh не найден в $(pwd)"
    elif ! grep -q "chmod" solution.sh; then
        bad "в solution.sh нет команд chmod"
    else
        ok "solution.sh есть"
        if git ls-files --error-unmatch solution.sh >/dev/null 2>&1; then ok "solution.sh добавлен в Git"
        else bad "solution.sh ещё не добавлен в Git (git add)"; fi
    fi
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "Все проверки прошли ✅"
else
    exit 1
fi
