#!/bin/bash
# Проверка Задачи 12. Запуск из папки задачи: bash check_task12.sh
# Запускает q1.sh … q6.sh на свежих файлах во временной папке и сравнивает
# вывод с эталоном. Проверяет answers.txt. Твои файлы не трогает.

cd "$(dirname "$0")" || exit 1
here=$(pwd)

tmp=$(mktemp -d)
cp setup.sh "$tmp"/
cd "$tmp" || exit 1
bash setup.sh > /dev/null

fails=0
ok()   { echo "  OK    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

# эталонные команды (вывод сравнивается, а не текст команды)
expected() {
    case "$1" in
        1) head -n 5 app.log ;;
        2) tail -n 3 app.log ;;
        3) tail -n +995 app.log ;;
        4) wc -l < app.log ;;
        5) cat -n nginx.conf ;;
        6) zcat old.log.gz ;;
    esac
}
names=("" "первые 5 строк app.log" "последние 3 строки app.log" "app.log со строки 995 до конца" \
       "количество строк в app.log" "nginx.conf с номерами строк" "содержимое old.log.gz без распаковки")

echo "Команды:"
for n in 1 2 3 4 5 6; do
    f="$here/q$n.sh"
    if [ ! -f "$f" ]; then
        fail "q$n.sh — нет файла (${names[$n]})"
        continue
    fi
    got=$(bash "$f" 2>&1)
    want=$(expected "$n")
    if [ "$n" -eq 4 ]; then
        got=$(echo "$got" | awk 'NR==1 {print $1}')   # «1000 app.log» и «1000» — оба верно
    fi
    if [ "$got" = "$want" ]; then
        ok "q$n.sh — ${names[$n]}"
    else
        fail "q$n.sh — ${names[$n]}"
        echo "        ожидалось (первые строки):"; echo "$want" | head -n 3 | sed 's/^/          /'
        echo "        получено  (первые строки):"; echo "$got"  | head -n 3 | sed 's/^/          /'
    fi
done

echo "Ответы (answers.txt):"
A="$here/answers.txt"
get() { [ -f "$A" ] && grep -E "^$1=" "$A" | head -n 1 | cut -d= -f2 | tr -d ' \r'; }
check_answer() { # ключ правильный_ответ описание
    local v; v=$(get "$1")
    if [ -z "$v" ]; then fail "$1 — нет ответа ($3)"
    elif [ "$v" = "$2" ]; then ok "$1=$v ($3)"
    else fail "$1=$v — неверно ($3)"; fi
}
check_answer panic_line     737          "номер строки с PANIC в app.log"
check_answer crlf_line      4            "строка nginx.conf с Windows-переводом строки"
check_answer trailing_line  5            "строка nginx.conf с пробелами в конце"
check_answer deploy_key     "juliet-17"   "ключ из live.log (tail -f)"

cd / && rm -rf "$tmp"
echo
if [ "$fails" -eq 0 ]; then
    echo "Все проверки прошли ✅"; exit 0
else
    echo "Не прошло проверок: $fails ❌"; exit 1
fi
