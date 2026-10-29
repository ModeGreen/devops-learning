#!/bin/bash
# Проверка Задачи 24. Запуск из папки задачи:
#   bash check_task24.sh      — всё
#   bash check_task24.sh 3    — только шаг 3 (и так же 1…6)
# Проверка сама ничего не ставит и не удаляет, sudo ей не нужен:
# она смотрит на систему (что установлено, что нет) и на answers.txt.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

# значение строки «ключ: значение» из answers.txt, без пробелов по краям
answer() {
    grep -m1 "^$1:" answers.txt 2>/dev/null | cut -d: -f2- | tr -d ' \r'
}

# статус пакета: installed / config-files / not-installed
pkg_state() {
    local s
    s=$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)
    case "$s" in
        *" installed") echo installed ;;
        *config-files) echo config-files ;;
        *) echo not-installed ;;
    esac
}

# пакет-библиотека jq из поля Depends той версии, которую ставит apt (libjq1)
jq_lib() {
    local cand
    cand=$(apt-cache policy jq 2>/dev/null | awk '/Candidate:/ {print $2}')
    apt-cache show "jq=$cand" 2>/dev/null | grep -m1 '^Depends:' | grep -o 'libjq[^ ,]*'
}

need_answers() {
    if [ ! -f answers.txt ]; then
        bad "answers.txt — нет файла (создай его в папке задачи)"
        return 1
    fi
}

if run_step 1; then
    echo "Шаг 1. Версия системы и каталог пакетов"
    if need_answers; then
        real=$(. /etc/os-release && echo "$VERSION_ID")
        got=$(answer ubuntu)
        if [ -z "$got" ]; then bad "answers.txt — нет строки ubuntu: …"
        elif [ "$got" == "$real" ]; then ok "ubuntu — верно ($real)"
        else bad "ubuntu — не то (часть 2 урока: какое поле — номер версии?)"; fi
    fi
    if [ -n "$(find /var/lib/apt/lists/partial -maxdepth 0 -mmin -720 2>/dev/null)" ]; then
        ok "каталог пакетов обновлялся за последние 12 часов"
    else
        bad "каталог пакетов давно не обновлялся — sudo apt update"
    fi
fi

if run_step 2; then
    echo "Шаг 2. Обновления"
    left=$(apt-get -s --with-new-pkgs upgrade 2>/dev/null | grep -c '^Inst ')
    if [ "$left" -eq 0 ]; then
        ok "обновлять нечего — система свежая"
    else
        bad "можно обновить ещё $left пакет(ов) — sudo apt upgrade (если apt пишет «deferred due to phasing» — напиши мне)"
    fi
fi

if run_step 3; then
    echo "Шаг 3. Паспорт пакета jq"
    if need_answers; then
        cand=$(apt-cache policy jq 2>/dev/null | awk '/Candidate:/ {print $2}')
        lib=$(jq_lib)
        got=$(answer jq-version)
        if [ -z "$cand" ] || [ "$cand" == "(none)" ]; then bad "apt не знает пакет jq — сначала sudo apt update"
        elif [ -z "$got" ]; then bad "answers.txt — нет строки jq-version: …"
        elif [ "$got" == "$cand" ]; then ok "jq-version — верно ($cand)"
        else bad "jq-version — не та версия (поле Version в apt show, целиком)"; fi
        got=$(answer jq-depends)
        if [ -z "$got" ]; then bad "answers.txt — нет строки jq-depends: …"
        elif [ "$got" == "$lib" ]; then ok "jq-depends — верно ($lib)"
        else bad "jq-depends — не то (поле Depends: имя пакета, без версии в скобках)"; fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. Установить ncdu и jq"
    for p in ncdu jq; do
        if [ "$(pkg_state $p)" == "installed" ]; then ok "$p установлен"
        else bad "$p не установлен"; fi
    done
    lib=$(jq_lib)
    if [ -n "$lib" ]; then
        if [ "$(pkg_state "$lib")" == "installed" ]; then ok "зависимость $lib apt поставил сам"
        else bad "зависимость $lib не установлена"; fi
    fi
    if need_answers; then
        real=$(command -v ncdu)
        got=$(answer ncdu-path)
        if [ -z "$got" ]; then bad "answers.txt — нет строки ncdu-path: …"
        elif [ -z "$real" ]; then bad "команды ncdu нет в системе — сначала установи"
        elif [ "$got" == "$real" ]; then ok "ncdu-path — верно ($real)"
        else bad "ncdu-path — не тот путь (часть 5 урока: какой командой узнать?)"; fi
    fi
fi

if run_step 5; then
    echo "Шаг 5. Убрать mc полностью"
    st=$(pkg_state mc)
    if [ "$st" == "installed" ]; then
        bad "mc ещё установлен"
    elif [ "$st" == "config-files" ] || [ -d /etc/mc ]; then
        bad "mc удалён, но его настройки остались в /etc/mc (часть 6.1 урока)"
    elif ! grep -q 'install .*mc' /var/log/apt/history.log 2>/dev/null; then
        bad "mc и не ставился — сначала bash setup.sh"
    else
        ok "mc удалён вместе с настройками, /etc/mc нет"
    fi
    if [ "$(pkg_state mc-data)" == "installed" ]; then
        bad "осталась зависимость mc-data — она больше не нужна (часть 6.2)"
    else
        ok "ненужная зависимость mc-data убрана"
    fi
fi

if run_step 6; then
    echo "Шаг 6. Git"
    for f in answers.txt setup.sh check_task24.sh; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f добавлен в Git"; else bad "$f не добавлен в Git"; fi
    done
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
