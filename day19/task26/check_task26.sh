#!/bin/bash
# Проверка Задачи 26. Запуск из папки задачи:
#   bash check_task26.sh      — всё
#   bash check_task26.sh 3    — только шаг 3 (и так же 1…7)
# Проверка сама ничего не запускает и не останавливает:
# она смотрит на службы shop-web и shop-mailer и на answers.txt.
# Журнал читает через sudo, если твоему пользователю он без sudo не виден.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0
SETUP_FILE=/var/tmp/task26.setup

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

# значение строки «ключ: значение» из answers.txt, без пробелов по краям
answer() {
    grep -m1 "^$1:" answers.txt 2>/dev/null | cut -d: -f2- | tr -d ' \r'
}

need_answers() {
    if [ ! -f answers.txt ]; then
        bad "answers.txt — нет файла (создай его в папке задачи)"
        return 1
    fi
}

need_setup() {
    if [ ! -f "$SETUP_FILE" ] || [ ! -f /etc/systemd/system/shop-web.service ]; then
        bad "службы не установлены — сначала bash setup.sh"
        return 1
    fi
}

# active / inactive / failed
state() { systemctl is-active "$1" 2>/dev/null; }

# журнал: без sudo, если пользователь в группе adm или systemd-journal
jr() {
    if id -nG | grep -qwE 'adm|systemd-journal'; then
        journalctl --no-pager -q "$@" 2>/dev/null
    else
        sudo journalctl --no-pager -q "$@" 2>/dev/null
    fi
}

if run_step 1; then
    echo "Шаг 1. Состояние shop-web"
    if [ "$(ps -p 1 -o comm=)" == "systemd" ]; then ok "systemd работает (PID 1)"
    else bad "PID 1 — не systemd: напиши Claude"; fi
    if need_setup && need_answers; then
        real=$(systemctl show -p FragmentPath --value shop-web 2>/dev/null)
        got=$(answer web-unit)
        if [ -z "$got" ]; then bad "answers.txt — нет строки web-unit: …"
        elif [ "$got" == "$real" ]; then ok "web-unit — верно ($real)"
        else bad "web-unit — не то (строка Loaded: путь в скобках, до ;)"; fi
        got=$(answer web-autostart)
        if [ -z "$got" ]; then bad "answers.txt — нет строки web-autostart: …"
        elif [ "$got" == "disabled" ]; then ok "web-autostart — верно (disabled: после setup.sh автозапуска нет)"
        else bad "web-autostart — не то (строка Loaded: слово после пути и ; — каким оно было до шага 3?)"; fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. Остановить, запустить, перезапустить"
    if need_setup; then
        since=$(cat "$SETUP_FILE")
        stops=$(jr -u shop-web --since "$since" | grep -cE 'Stopped (shop-web\.service|Shop web)')
        if [ "$stops" -ge 2 ]; then ok "shop-web останавливали после setup.sh: $stops раз(а) — stop и restart"
        else bad "shop-web останавливали после setup.sh: $stops раз(а) — нужны и stop, и restart (часть 3)"; fi
        st=$(state shop-web)
        if [ "$st" == "active" ]; then ok "shop-web сейчас работает"
        else bad "shop-web сейчас не работает ($st) — запусти её"; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Автозапуск shop-web"
    if need_setup; then
        a=$(systemctl is-enabled shop-web 2>/dev/null)
        if [ "$a" == "enabled" ]; then ok "автозапуск shop-web включён"
        else bad "автозапуск shop-web: $a — а нужен enabled (часть 4)"; fi
        st=$(state shop-web)
        if [ "$st" == "active" ]; then ok "shop-web работает"
        else bad "shop-web не работает ($st) — enable не запускает службу (часть 4)"; fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. Журнал shop-web"
    if need_answers; then
        got=$(answer web-port)
        if [ -z "$got" ]; then bad "answers.txt — нет строки web-port: …"
        elif [ "$got" == "8081" ]; then ok "web-port — верно (8081)"
        else bad "web-port — не то (строка самой службы сразу после Started… — часть 6.1)"; fi
    fi
fi

if run_step 5; then
    echo "Шаг 5. Что упало"
    if need_answers; then
        got=$(answer failed-service)
        got=${got%.service}
        if [ -z "$got" ]; then bad "answers.txt — нет строки failed-service: …"
        elif [ "$got" == "shop-mailer" ]; then ok "failed-service — верно (shop-mailer.service)"
        else bad "failed-service — не та служба (часть 5)"; fi
        got=$(answer mailer-config)
        if [ -z "$got" ]; then bad "answers.txt — нет строки mailer-config: …"
        elif [ "$got" == "/etc/shop/mailer.conf" ]; then ok "mailer-config — верно (/etc/shop/mailer.conf)"
        else bad "mailer-config — не то (строка ОШИБКА в журнале службы — часть 6.1)"; fi
    fi
fi

if run_step 6; then
    echo "Шаг 6. Починить shop-mailer"
    if need_setup; then
        if grep -qs '^smtp_host=..*' /etc/shop/mailer.conf; then
            fixed=yes
            ok "в /etc/shop/mailer.conf есть строка smtp_host=…"
        else
            fixed=no
            bad "в /etc/shop/mailer.conf нет строки smtp_host=… (что просит сообщение ОШИБКА?)"
        fi
        st=$(state shop-mailer)
        if [ "$st" == "active" ]; then ok "shop-mailer работает"
        elif [ "$fixed" == "yes" ]; then bad "файл есть, а shop-mailer не работает ($st) — службу надо поднять заново (часть 3)"
        else bad "shop-mailer не работает ($st)"; fi
    fi
fi

if run_step 7; then
    echo "Шаг 7. Git"
    for f in answers.txt setup.sh check_task26.sh cleanup.sh; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f добавлен в Git"; else bad "$f не добавлен в Git"; fi
    done
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
