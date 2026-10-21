#!/bin/bash
# Проверка Задачи 17.
#   bash check_task17.sh      — всё
#   bash check_task17.sh 2    — только шаг 2 (и так же 3, 4, 5, 6)
# Запускать без sudo. Шаги 3 и 4 сами попросят пароль sudo.
APP=/srv/shop
ME=$(whoami)
STEP="${1:-all}"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

# full: путь права владелец группа (stat через sudo — часть файлов уже не твоя)
full() {
    local got
    got=$(sudo stat -c '%a %U:%G' "$1" 2>/dev/null)
    if [ -z "$got" ]; then bad "$1 не найден"; return; fi
    if [ "$got" == "$2 $3:$4" ]; then ok "$1: $got"; else bad "$1: сейчас $got, нужно $2 $3:$4"; fi
}

# as_app: описание ожидание(yes/no) команда... — выполняет команду от имени shopapp
as_app() {
    local text="$1" want="$2" got
    shift 2
    if sudo -u shopapp "$@" >/dev/null 2>&1; then got=yes; else got=no; fi
    if [ "$got" == "$want" ]; then ok "$text"; else bad "$text"; fi
}

if [ "$ME" == "root" ]; then
    echo "❌ Запусти без sudo: bash check_task17.sh"
    exit 1
fi
if [ ! -d "$APP" ]; then
    echo "❌ $APP не найден — сначала bash setup.sh"
    exit 1
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "2" ]; then
    echo "Шаг 2. Группа и пользователь"
    if getent group shop >/dev/null; then ok "группа shop есть"; else bad "группы shop нет"; fi
    if id shopapp >/dev/null 2>&1; then
        ok "пользователь shopapp есть"
        if [ "$(id -u shopapp)" -lt 1000 ]; then ok "shopapp системный (UID $(id -u shopapp) < 1000)"
        else bad "UID shopapp — $(id -u shopapp), нужен меньше 1000 (--system)"; fi
        if [ "$(id -gn shopapp)" == "shop" ]; then ok "основная группа shopapp — shop"
        else bad "основная группа shopapp — $(id -gn shopapp), нужно shop"; fi
        shell=$(getent passwd shopapp | cut -d: -f7)
        if [ "$shell" == "/usr/sbin/nologin" ]; then ok "shopapp не может войти в систему (nologin)"
        else bad "оболочка shopapp — $shell, нужно /usr/sbin/nologin"; fi
    else
        bad "пользователя shopapp нет"
    fi
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "3" ]; then
    echo "Шаг 3. Владельцы (нужен sudo)"
    full "$APP" 755 "$ME" "$ME"
    full "$APP/.env" 600 shopapp shop
    full "$APP/logs" 755 shopapp shop
    full "$APP/logs/app.log" 644 shopapp shop
    full "$APP/config.yaml" 640 "$ME" shop
    full "$APP/deploy.sh" 755 "$ME" "$ME"
    full "$APP/keys" 700 "$ME" "$ME"
    full "$APP/keys/id_deploy" 600 "$ME" "$ME"
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "4" ]; then
    echo "Шаг 4. Что может shopapp (нужен sudo)"
    if ! id shopapp >/dev/null 2>&1; then
        bad "пользователя shopapp нет — сначала шаг 2"
    else
        as_app "shopapp читает config.yaml"           yes cat "$APP/config.yaml"
        as_app "shopapp читает .env"                  yes cat "$APP/.env"
        as_app "shopapp пишет в logs/"                yes touch "$APP/logs/.check"
        sudo rm -f "$APP/logs/.check"
        as_app "shopapp НЕ меняет config.yaml"        no  sh -c "echo x >> '$APP/config.yaml'"
        as_app "shopapp НЕ видит список keys/"        no  ls "$APP/keys"
        as_app "shopapp НЕ читает keys/id_deploy"     no  cat "$APP/keys/id_deploy"
        as_app "shopapp НЕ создаёт файлы в /srv/shop" no  touch "$APP/.check"
        sudo rm -f "$APP/.check"
    fi
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "5" ]; then
    echo "Шаг 5. Ты в группе shop"
    if id -nG "$ME" | grep -qw shop; then ok "$ME записан в группу shop"
    else bad "$ME не в группе shop"; fi
    others=$(id -nG "$ME" | grep -qw sudo && echo yes)
    if [ "$others" == "yes" ]; then ok "$ME остался в группе sudo (значит, был -a)"
    else bad "$ME больше не в группе sudo — вероятно, usermod без -a (см. подсказки)"; fi
fi

if [ "$STEP" == "all" ] || [ "$STEP" == "6" ]; then
    echo "Шаг 6. solution.sh в Git (запускать из папки задачи)"
    if [ ! -f solution.sh ]; then
        bad "solution.sh не найден в текущей папке ($(pwd))"
    else
        ok "solution.sh есть"
        for cmd in groupadd useradd chown usermod; do
            if grep -q "$cmd" solution.sh; then ok "в solution.sh есть $cmd"
            else bad "в solution.sh нет $cmd"; fi
        done
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
