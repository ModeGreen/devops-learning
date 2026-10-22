#!/bin/bash
# Проверка Задачи 18. Запуск из папки задачи:
#   bash check_task18.sh      — всё
#   bash check_task18.sh 2    — только шаг 2 (и так же 1, 3, 4, 5, 6, 7)
# Каждый qN.sh запускается на СВЕЖЕЙ копии shop/ во временной папке,
# вывод сравнивается с эталоном. Твою папку shop/ проверка не трогает.

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

# эталонные команды
expected() {
    case "$1" in
        1)  grep 'ERROR' shop/logs/app.log ;;
        2)  grep -in 'error' shop/logs/app.log ;;
        3)  grep -c 'ERROR' shop/logs/app.log ;;
        4)  grep -v '^#' shop/config/nginx.conf ;;
        5)  grep -rl 'db.internal' shop ;;
        6)  find shop -name '*.yaml' ;;
        7)  find shop -type d ;;
        8)  find shop/logs -mtime +7 ;;
        9)  find shop -size +1M ;;
        10) find shop/logs -mtime +7 -delete ;;
    esac
}

text=("" \
  "строки с ERROR (большими буквами) в app.log" \
  "строки с error в любом регистре, с номерами строк" \
  "сколько строк с ERROR в app.log" \
  "nginx.conf без строк-комментариев" \
  "имена файлов в shop/, где есть db.internal" \
  "все файлы .yaml в shop/" \
  "все папки в shop/" \
  "файлы в shop/logs старше 7 дней" \
  "файлы в shop/ больше 1 МБ" \
  "удалить файлы в shop/logs старше 7 дней")

# для find и grep -r порядок строк не важен: сортируем, убираем ./ и лишние /
norm()   { sed -e 's#^\./##' -e 's#//*#/#g' -e 's#/$##'; }
sorted() { [ "$1" -ge 5 ] && [ "$1" -le 9 ]; }

# путь должен быть относительным: shop/...
bad_path() { grep -qE '~|/home/|/mnt/|(^|[ ;])cd ' "$1"; }

check_q() {
    local n=$1 f="$here/q$1.sh" t got want
    if [ ! -f "$f" ]; then bad "q$n.sh — нет файла (${text[$n]})"; return; fi
    if bad_path "$f"; then bad "q$n.sh — путь должен начинаться с shop/ (без cd, ~ и /home)"; return; fi
    t=$(fresh)
    got=$(cd "$t" && bash "$f" 2>&1)
    want=$(cd "$t" && expected "$n" 2>&1)
    if sorted "$n"; then
        got=$(echo "$got" | norm | sort)
        want=$(echo "$want" | norm | sort)
    fi
    rm -rf "$t"
    if [ "$got" == "$want" ]; then
        ok "q$n.sh — ${text[$n]}"
    else
        bad "q$n.sh — ${text[$n]}"
        echo "        ожидалось (первые строки):"; echo "$want" | head -n 4 | sed 's/^/          /'
        echo "        получено  (первые строки):"; echo "$got"  | head -n 4 | sed 's/^/          /'
    fi
}

# q10 удаляет файлы — сравниваем, что осталось в shop/ после команды
check_delete() {
    local f="$here/q10.sh" a b got want
    if [ ! -f "$f" ]; then bad "q10.sh — нет файла (${text[10]})"; return; fi
    if bad_path "$f"; then bad "q10.sh — путь должен начинаться с shop/ (без cd, ~ и /home)"; return; fi
    if ! grep -q -- '-delete' "$f"; then bad "q10.sh — в команде нет -delete"; return; fi
    a=$(fresh); b=$(fresh)
    (cd "$a" && bash "$f" > /dev/null 2>&1)
    (cd "$b" && expected 10 > /dev/null 2>&1)
    got=$(cd "$a" && find shop | sort)
    want=$(cd "$b" && find shop | sort)
    rm -rf "$a" "$b"
    if [ "$got" == "$want" ]; then
        ok "q10.sh — удалены только app.log.2 и app.log.3, остальное на месте"
    else
        bad "q10.sh — после команды в shop/ осталось не то, что нужно"
        lost=$(comm -13 <(echo "$got") <(echo "$want"))
        extra=$(comm -23 <(echo "$got") <(echo "$want"))
        [ -n "$lost" ]  && { echo "        удалено лишнее:";  echo "$lost"  | sed 's/^/          /'; }
        [ -n "$extra" ] && { echo "        не удалено:";      echo "$extra" | sed 's/^/          /'; }
    fi
}

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

if run_step 1; then echo "Шаг 1. grep, -i, -n"; check_q 1; check_q 2; fi
if run_step 2; then echo "Шаг 2. -c, -v, ^";   check_q 3; check_q 4; fi
if run_step 3; then echo "Шаг 3. grep по папке"; check_q 5; fi
if run_step 4; then echo "Шаг 4. find -name, -type"; check_q 6; check_q 7; fi
if run_step 5; then echo "Шаг 5. find -mtime, -size"; check_q 8; check_q 9; fi
if run_step 6; then echo "Шаг 6. find -delete"; check_delete; fi
if run_step 7; then
    echo "Шаг 7. Git"
    for n in 1 2 3 4 5 6 7 8 9 10; do
        if ! git ls-files --error-unmatch "q$n.sh" >/dev/null 2>&1; then missing="$missing q$n.sh"; fi
    done
    if [ -z "$missing" ]; then ok "q1.sh … q10.sh добавлены в Git"; else bad "не добавлены в Git:$missing"; fi
    for f in setup.sh check_task18.sh .gitignore; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f добавлен в Git"; else bad "$f не добавлен в Git"; fi
    done
    if git check-ignore -q shop/logs/app.log 2>/dev/null; then ok "shop/ не попадёт в Git (.gitignore)"
    else bad "shop/ не в .gitignore — сгенерированные файлы попадут в Git"; fi
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
