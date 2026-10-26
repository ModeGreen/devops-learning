#!/bin/bash
# Проверка Задачи 21. Запуск из папки задачи:
#   bash check_task21.sh      — всё
#   bash check_task21.sh 3    — только шаг 3 (и так же 1…8)
# Каждый qN.sh запускается на СВЕЖЕЙ копии shop/ во временной папке.
# Сравнивается с эталоном: что напечаталось на экран (вывод + ошибки)
# и что лежит в shop/reports/ после команды. Твою папку shop/ проверка не трогает.

cd "$(dirname "$0")" || exit 1
here=$(pwd)
STEP="${1:-all}"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

# свежая копия shop/ во временной папке
fresh() {
    local t
    t=$(mktemp -d)
    cp "$here/setup.sh" "$t"/
    (cd "$t" && bash setup.sh > /dev/null)
    echo "$t"
}
cleanup() { chmod -R u+rwx "$1" 2>/dev/null; rm -rf "$1"; }

# эталонные команды
expected() {
    case "$1" in
        1)  grep 'ERROR' shop/logs/app.log > shop/reports/errors.txt ;;
        2)  echo '2026-10-26 логи проверены' >> shop/reports/duty.log ;;
        3)  find shop -name '*.conf' 2>/dev/null ;;
        4)  bash shop/bin/healthcheck.sh > shop/reports/health.txt 2> shop/reports/health-errors.txt ;;
        5)  bash shop/bin/healthcheck.sh > shop/reports/health-all.log 2>&1 ;;
        6)  grep 'ERROR' shop/logs/app.log | grep -v 'db timeout' ;;
        7)  grep 'ERROR' shop/logs/app.log | grep -v 'db timeout' | wc -l ;;
        8)  cut -d' ' -f1 shop/logs/access.log ;;
        9)  cut -d' ' -f1 shop/logs/access.log | sort | uniq -c ;;
        10) cut -d' ' -f1 shop/logs/access.log | sort | uniq -c | sort -rn | head -n 3 > shop/reports/top-ip.txt ;;
    esac
}

text=("" \
  "строки с ERROR из app.log → reports/errors.txt (запуск 2 раза — без дублей)" \
  "дописать строку в конец reports/duty.log" \
  "все .conf в shop/ без сообщений об ошибках" \
  "проверка: вывод → health.txt, ошибки → health-errors.txt" \
  "проверка: вывод и ошибки → один файл health-all.log" \
  "строки с ERROR, кроме db timeout" \
  "сколько строк с ERROR, кроме db timeout" \
  "только IP-адреса из access.log" \
  "сколько запросов с каждого IP" \
  "топ-3 IP → reports/top-ip.txt")

# сколько раз запускать команду: q1 — дважды (перезапись не должна давать дубли)
times() { [ "$1" -eq 1 ] && echo 2 || echo 1; }

# путь должен быть относительным: shop/...
bad_path() { grep -qE '~|/home/|/mnt/|(^|[ ;])cd ' "$1"; }

# всё, что лежит в shop/reports/: имя файла + содержимое
reports() { (cd "$1/shop/reports" && for f in *; do echo "=== $f"; cat "$f"; done); }

# для find порядок строк не важен
norm() { sed -e 's#^\./##' -e 's#//*#/#g' | sort; }

show() {
    echo "        $1"
    if [ -z "$2" ]; then echo "          (пусто)"; else echo "$2" | head -n 6 | sed 's/^/          /'; fi
}

check_q() {
    local n=$1 f="$here/q$1.sh" a b k got want rgot rwant
    if [ ! -f "$f" ]; then bad "q$n.sh — нет файла (${text[$n]})"; return; fi
    if bad_path "$f"; then bad "q$n.sh — путь должен начинаться с shop/ (без cd, ~ и /home)"; return; fi
    if [[ " 6 7 9 10 " == *" $n "* ]] && ! grep -q '|' "$f"; then bad "q$n.sh — в команде нет пайпа |"; return; fi
    a=$(fresh); b=$(fresh)
    for k in $(seq 1 "$(times "$n")"); do
        got=$(cd "$a" && bash "$f" 2>&1)
        want=$(cd "$b" && expected "$n" 2>&1)
    done
    if [ "$n" -eq 3 ]; then got=$(echo "$got" | norm); want=$(echo "$want" | norm); fi
    rgot=$(reports "$a"); rwant=$(reports "$b")
    cleanup "$a"; cleanup "$b"
    if [ "$got" == "$want" ] && [ "$rgot" == "$rwant" ]; then
        ok "q$n.sh — ${text[$n]}"
        return
    fi
    bad "q$n.sh — ${text[$n]}"
    if [ "$got" != "$want" ]; then
        show "на экран ожидалось (первые строки):" "$want"
        show "на экран получено  (первые строки):" "$got"
    fi
    if [ "$rgot" != "$rwant" ]; then
        echo "        в shop/reports/ не то, что нужно — сравни:"
        diff <(echo "$rwant") <(echo "$rgot") | grep '^[<>]' | head -n 8 \
            | sed -e 's/^</          нужно:   /' -e 's/^>/          у тебя:  /'
    fi
}

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

if run_step 1; then echo "Шаг 1. > и >>"; check_q 1; check_q 2; fi
if run_step 2; then echo "Шаг 2. 2>/dev/null"; check_q 3; fi
if run_step 3; then echo "Шаг 3. 2> и 2>&1"; check_q 4; check_q 5; fi
if run_step 4; then echo "Шаг 4. пайп |"; check_q 6; check_q 7; fi
if run_step 5; then echo "Шаг 5. cut"; check_q 8; fi
if run_step 6; then echo "Шаг 6. sort | uniq -c"; check_q 9; fi
if run_step 7; then echo "Шаг 7. sort -rn | head > файл"; check_q 10; fi
if run_step 8; then
    echo "Шаг 8. Git"
    missing=""
    for n in 1 2 3 4 5 6 7 8 9 10; do
        if ! git ls-files --error-unmatch "q$n.sh" >/dev/null 2>&1; then missing="$missing q$n.sh"; fi
    done
    if [ -z "$missing" ]; then ok "q1.sh … q10.sh добавлены в Git"; else bad "не добавлены в Git:$missing"; fi
    for f in setup.sh check_task21.sh .gitignore; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f добавлен в Git"; else bad "$f не добавлен в Git"; fi
    done
    if git check-ignore -q shop/logs/app.log 2>/dev/null; then ok "shop/ не попадёт в Git (.gitignore)"
    else bad "shop/ не в .gitignore — сгенерированные файлы попадут в Git"; fi
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
