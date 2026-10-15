#!/bin/bash
# Проверка Задачи 11. Запуск из папки задачи: bash check_task11.sh
# Скрипт копирует setup.sh и solution.sh во временную папку,
# запускает их там и проверяет результат. Твои файлы не трогает.

cd "$(dirname "$0")" || exit 1

for f in setup.sh solution.sh; do
    if [ ! -f "$f" ]; then
        echo "ОШИБКА: нет файла $f рядом с check_task11.sh"
        exit 1
    fi
done

tmp=$(mktemp -d)
cp setup.sh solution.sh "$tmp"/
cd "$tmp" || exit 1

bash setup.sh > /dev/null
echo "--- вывод solution.sh ---"
bash solution.sh
code=$?
echo "--- конец вывода (код возврата: $code) ---"
echo

fails=0
ok()   { echo "  OK    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { # check "описание" команда...
    local name="$1"; shift
    if "$@"; then ok "$name"; else fail "$name"; fi
}
same() { [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; }

# Эталонное содержимое, чтобы сравнивать файлы
mkdir ref && cp setup.sh ref/ && bash ref/setup.sh > /dev/null
R=ref/incoming

echo "Структура:"
for d in logs configs backups archive; do
    check "папка server/$d" test -d "server/$d"
done

echo "Логи (mv):"
for f in app.log app.log.1 app.log.2 error.log; do
    check "server/logs/$f с исходным содержимым" same "server/logs/$f" "$R/$f"
    check "incoming/$f больше нет" test ! -e "incoming/$f"
done

echo "Конфиги (mv + cp с переименованием):"
for f in nginx.conf app.conf; do
    check "server/configs/$f" same "server/configs/$f" "$R/$f"
    check "server/backups/$f.bak — копия" same "server/backups/$f.bak" "$R/$f"
    check "incoming/$f больше нет" test ! -e "incoming/$f"
done

echo "Старые конфиги (папка целиком):"
check "server/archive/old_configs/old1.conf" same server/archive/old_configs/old1.conf "$R/old_configs/old1.conf"
check "server/archive/old_configs/old2.conf" same server/archive/old_configs/old2.conf "$R/old_configs/old2.conf"
check "incoming/old_configs больше нет" test ! -e incoming/old_configs

echo "Временные файлы:"
leftover=$(find . -path ./ref -prune -o -name 'cache_*.tmp' -print | wc -l)
check "все cache_*.tmp удалены (осталось: $leftover)" test "$leftover" -eq 0
check "incoming/important.tmp на месте и не изменён" same incoming/important.tmp "$R/important.tmp"

echo "Файл с пробелом:"
check "server/report_final.txt" same server/report_final.txt "$R/report final.txt"
check "«incoming/report final.txt» больше нет" test ! -e "incoming/report final.txt"

echo "Пустая папка и маркер:"
check "incoming/empty удалена" test ! -e incoming/empty
check "server/.cleaned_at существует и пустой" bash -c '[ -f server/.cleaned_at ] && [ ! -s server/.cleaned_at ]'

echo "Итог в incoming/:"
rest=$(ls -A incoming 2>/dev/null)
check "в incoming/ остался только important.tmp (сейчас: ${rest//$'\n'/, })" test "$rest" = "important.tmp"

echo "Правила:"
check "solution.sh без rm -f / rm -rf" bash -c '! grep -Eq "rm[[:space:]]+(-[a-zA-Z]*f|.*[[:space:]]-[a-zA-Z]*f)" "$0"' solution.sh
check "solution.sh без sudo" bash -c '! grep -q "sudo" "$0"' solution.sh

cd / && rm -rf "$tmp"
echo
if [ "$fails" -eq 0 ]; then
    echo "Все проверки прошли ✅"
    exit 0
else
    echo "Не прошло проверок: $fails ❌"
    exit 1
fi
