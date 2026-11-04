#!/bin/bash
# Проверка Задачи 28. Запуск из папки задачи:
#   bash check_task28.sh      — всё
#   bash check_task28.sh 3    — только шаг 3 (и так же 1…6)
# Проверка запускает твой ./check_shop.sh на своих временных папках shop
# (в /tmp, в имени папки есть пробел) и смотрит на код возврата, stdout и stderr.
# Твою папку ~/task28 она не трогает.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0
SCRIPT=./check_shop.sh

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BASE="$TMP/my shops"

# make_shop папка число_ошибок есть_config есть_лог — как в setup.sh
make_shop() {
    local dir="$BASE/$1"
    mkdir -p "$dir"
    if [ "$3" == "yes" ]; then
        printf 'port: 8081\n' > "$dir/config.yaml"
    fi
    if [ "$4" == "yes" ]; then
        mkdir -p "$dir/logs"
        local log="$dir/logs/app.log"
        : > "$log"
        echo "2026-11-04 10:00:01 INFO заказ #1 принят" >> "$log"
        echo "2026-11-04 10:00:30 WARN медленный ответ базы" >> "$log"
        for i in $(seq 1 "$2"); do
            echo "2026-11-04 10:01:00 ERROR оплата заказа #$i не прошла" >> "$log"
        done
        echo "2026-11-04 10:02:00 INFO заказ #2 принят" >> "$log"
    fi
}

make_shop "ok"        0  yes yes
make_shop "no config" 0  no  yes
make_shop "no log"    0  yes no
for n in 1 9 10 25; do make_shop "errors $n" "$n" yes yes; done

# run аргументы… → OUT, ERR, CODE
run() {
    OUT=$(timeout 5 "$SCRIPT" "$@" 2>"$TMP/stderr" </dev/null)
    CODE=$?
    ERR=$(cat "$TMP/stderr")
}

# скрипт на месте и запускается — иначе дальше проверять нечего
need_script() {
    if [ ! -f "$SCRIPT" ]; then
        bad "нет файла check_shop.sh в папке задачи"
        return 1
    fi
    if [ ! -x "$SCRIPT" ]; then
        bad "check_shop.sh не запускается как программа — нет права x (урок 11, часть 1)"
        return 1
    fi
}

# в stderr ничего лишнего (сообщения вида «[: too many arguments» — признак переменной без кавычек)
clean_stderr() {
    if [ -n "$ERR" ]; then
        bad "$1: в stderr что-то есть: $(echo "$ERR" | head -n 1)"
        return 1
    fi
    return 0
}

if run_step 1; then
    echo "Шаг 1. Скрипт и первая строка"
    if need_script; then
        ok "check_shop.sh есть и запускается"
        if [ "$(head -n 1 "$SCRIPT")" == "#!/bin/bash" ]; then ok "первая строка — #!/bin/bash"
        else bad "первая строка не #!/bin/bash (шебанг — часть 1)"; fi
        if grep -q $'\r' "$SCRIPT"; then bad "в файле Windows-переводы строк (^M) — в VS Code внизу справа CRLF → LF"
        else ok "переводы строк Linux (LF)"; fi
        run "$BASE/ok"
        want="Проверка shop на сервере $(hostname)"
        got=$(echo "$OUT" | head -n 1)
        if [ "$got" == "$want" ]; then ok "первая строка вывода: $want"
        else bad "первая строка вывода: «$got», а ждём «$want»"; fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. Аргумент — папка shop"
    if need_script; then
        run
        if [ "$CODE" -eq 3 ]; then ok "без аргумента — код 3"
        else bad "без аргумента — код $CODE, а ждём 3 (UNKNOWN: проверка не может работать)"; fi
        if echo "$ERR" | grep -q "ОШИБКА"; then ok "без аргумента — ОШИБКА в stderr"
        else bad "без аргумента — в stderr нет слова ОШИБКА (часть 5: >&2)"; fi
        if echo "$OUT" | grep -q "ОШИБКА"; then bad "без аргумента — ОШИБКА попала в stdout, а нужна в stderr"
        else ok "в stdout ОШИБКИ нет"; fi
        run "$BASE/ok"
        got=$(echo "$OUT" | sed -n 2p)
        if [ "$got" == "Папка: $BASE/ok" ]; then ok "вторая строка вывода: Папка: …/my shops/ok"
        else bad "вторая строка вывода: «$got», а ждём «Папка: $BASE/ok»"; fi
        if [ "$CODE" -ne 3 ]; then ok "с аргументом — не код 3"
        else bad "с аргументом скрипт тоже вернул 3"; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Папки нет"
    if need_script; then
        run "$BASE/nope"
        if [ "$CODE" -eq 3 ]; then ok "нет папки — код 3"
        else bad "нет папки — код $CODE, а ждём 3"; fi
        if echo "$ERR" | grep -q "ОШИБКА" && echo "$ERR" | grep -qF "$BASE/nope"; then ok "нет папки — ОШИБКА с путём к папке в stderr"
        else bad "нет папки — в stderr нужна строка с ОШИБКА и путём к папке. Сейчас: «$(echo "$ERR" | head -n 1)»"; fi
        run "$BASE/ok"
        if [ "$CODE" -ne 3 ]; then ok "папка есть — не код 3"
        else bad "папка $BASE/ok есть (в имени пробел!), а скрипт вернул 3 — кавычки вокруг переменной? (часть 2)"; fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. config.yaml и лог на месте"
    if need_script; then
        run "$BASE/no config"
        if [ "$CODE" -eq 2 ] && echo "$OUT" | grep -q "^CRITICAL.*config.yaml"; then ok "нет config.yaml — CRITICAL и код 2"
        else bad "нет config.yaml — ждём строку CRITICAL: … config.yaml и код 2. Сейчас код $CODE, вывод: «$(echo "$OUT" | tail -n 1)»"; fi
        clean_stderr "нет config.yaml"
        run "$BASE/no log"
        if [ "$CODE" -eq 2 ] && echo "$OUT" | grep -q "^CRITICAL.*logs/app.log"; then ok "нет logs/app.log — CRITICAL и код 2"
        else bad "нет logs/app.log — ждём строку CRITICAL: … logs/app.log и код 2. Сейчас код $CODE, вывод: «$(echo "$OUT" | tail -n 1)»"; fi
        clean_stderr "нет лога"
        run "$BASE/ok"
        if [ "$CODE" -eq 0 ]; then ok "всё на месте, ошибок в логе нет — код 0"
        else bad "всё на месте, ошибок в логе нет — код $CODE, а ждём 0"; fi
        clean_stderr "всё на месте" && ok "в stderr пусто"
    fi
fi

if run_step 5; then
    echo "Шаг 5. Ошибки в логе"
    # папка  ожидаемый_код  статус
    while read -r name want status; do
        n=${name#errors_}
        [ "$name" == "ok" ] && n=0
        dir="$BASE/${name//_/ }"
        run "$dir"
        last=$(echo "$OUT" | tail -n 1)
        if [ "$CODE" -eq "$want" ] && [ "$last" == "$status: ошибок в логе: $n" ]; then
            ok "ERROR в логе: $n — «$last», код $CODE"
        else
            bad "ERROR в логе: $n — ждём «$status: ошибок в логе: $n» и код $want. Сейчас: «$last», код $CODE"
        fi
        clean_stderr "ERROR в логе: $n"
    done <<'EOF'
ok 0 OK
errors_1 1 WARNING
errors_9 1 WARNING
errors_10 2 CRITICAL
errors_25 2 CRITICAL
EOF
fi

if run_step 6; then
    echo "Шаг 6. Git и README"
    for f in check_shop.sh setup.sh check_task28.sh real_run.txt; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f добавлен в Git"; else bad "$f не добавлен в Git"; fi
    done
    mode=$(git ls-files -s check_shop.sh 2>/dev/null | cut -d' ' -f1)
    if [ "$mode" == "100755" ]; then ok "check_shop.sh в Git с правом x (100755)"
    else bad "check_shop.sh в Git без права x ($mode) — chmod +x и снова add + commit"; fi
    if [ -f real_run.txt ] && [ "$(wc -l < real_run.txt)" -ge 5 ]; then ok "real_run.txt — есть запуски"
    else bad "real_run.txt — нет файла или в нём меньше 5 строк"; fi
    readme="$(git rev-parse --show-toplevel 2>/dev/null)/README.md"
    if grep -q '`day21/`' "$readme" 2>/dev/null; then ok "в README есть строка day21/"
    else bad "в README нет строки для day21/"; fi
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
