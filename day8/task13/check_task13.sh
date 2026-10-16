#!/bin/bash
# Проверка Задачи 13. Запуск из папки задачи: bash check_task13.sh
# Сравнивает твой config.yaml с эталоном, проверяет бэкап, ~/.nanorc и редактор Git.
# Твои файлы не трогает.

cd "$(dirname "$0")" || exit 1
here=$(pwd)

tmp=$(mktemp -d)
cp setup.sh "$tmp"/
( cd "$tmp" && bash setup.sh > /dev/null )
orig="$tmp/config.yaml"

# эталон = оригинал + правки из условия
sed -e '/# --- BEGIN legacy ---/,/^$/d' \
    -e 's/^  debug: true$/  debug: false/' \
    -e 's/^  port: 8008$/  port: 8080/' \
    -e 's/old-db\.local/db.internal/g' "$orig" > "$tmp/expected.yaml"
printf '\nhealthcheck:\n  path: /health\n  interval: 10\n' >> "$tmp/expected.yaml"

fails=0
ok()   { echo "  OK    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

C="$here/config.yaml"
echo "config.yaml:"
if [ ! -f "$C" ]; then
    fail "нет файла config.yaml (запусти bash setup.sh)"
else
    grep -q $'\t' "$C" && fail "в файле есть Tab — в YAML отступы только пробелами" || ok "нет табов"
    grep -q $'\r' "$C" && fail "есть Windows-переводы строк (^M)" || ok "нет Windows-переводов строк"
    grep -qx '  debug: false' "$C" && ok "debug выключен" || fail "debug: должно быть false"
    grep -qx '  port: 8080' "$C" && ! grep -q '8008' "$C" && ok "порт сервера 8080" || fail "порт сервера: 8008 → 8080"
    n_old=$(grep -c 'old-db.local' "$C"); n_new=$(grep -c 'db.internal' "$C")
    [ "$n_old" -eq 0 ] && [ "$n_new" -eq 4 ] && ok "old-db.local → db.internal (4 замены)" \
        || fail "замена хоста: осталось old-db.local: $n_old, найдено db.internal: $n_new (нужно 0 и 4)"
    grep -q 'legacy' "$C" && fail "блок legacy не удалён" || ok "блок legacy удалён"
    grep -qx 'healthcheck:' "$C" && ok "секция healthcheck есть" || fail "нет секции healthcheck"
    if diff -q "$tmp/expected.yaml" "$C" > /dev/null; then
        ok "файл целиком совпадает с эталоном"
    else
        fail "файл целиком не совпадает с эталоном. Разница (< эталон, > твой файл):"
        diff "$tmp/expected.yaml" "$C" | head -n 20 | sed 's/^/          /'
    fi
fi

echo "Бэкап:"
if [ ! -f "$here/config.yaml.bak" ]; then
    fail "нет config.yaml.bak (копия до правок)"
elif cmp -s "$orig" "$here/config.yaml.bak"; then
    ok "config.yaml.bak — нетронутый оригинал"
else
    fail "config.yaml.bak отличается от оригинала (копию надо было сделать ДО правок)"
fi

echo "Настройки:"
R="$HOME/.nanorc"
for s in linenumbers tabstospaces "tabsize 4"; do
    if [ -f "$R" ] && grep -Eq "^[[:space:]]*set[[:space:]]+${s// /[[:space:]]+}[[:space:]]*$" "$R"; then
        ok "~/.nanorc: set $s"
    else
        fail "~/.nanorc: нет строки set $s"
    fi
done
ed=$(git config --global core.editor)
[[ "$ed" == *nano* ]] && ok "редактор Git: $ed" || fail "редактор Git не nano (сейчас: '${ed:-не задан}')"

cd / && rm -rf "$tmp"
echo
if [ "$fails" -eq 0 ]; then
    echo "Все проверки прошли ✅"; exit 0
else
    echo "Не прошло проверок: $fails ❌"; exit 1
fi
