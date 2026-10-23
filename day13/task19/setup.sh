#!/bin/bash
# Задача 19: создаёт учебный репозиторий shop-repo/ с историей коллег.
# ⚠️ Повторный запуск удаляет shop-repo/ и создаёт его заново (твои ветки и коммиты в нём пропадут).

cd "$(dirname "$0")" || exit 1
rm -rf shop-repo
mkdir shop-repo
cd shop-repo || exit 1

# коммиты «коллег» — под их именами, твой git config не трогаем
as() { GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2@shop.example" \
       GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2@shop.example" \
       git commit -q -m "$3"; }

git init -q -b main

cat > config.yaml <<'YAML'
# Конфиг сервиса shop
service: shop
port: 8080
workers: 2

database:
  host: db.internal
  name: shop

logging:
  level: info
YAML
cat > README.md <<'MD'
# shop
Интернет-магазин. Настройки — в `config.yaml`.
MD
git add config.yaml README.md
as "Anna" anna "Add shop config and README"

# ветка коллеги: меняет порт на 9090
git switch -q -c change-port
sed -i 's/^port: 8080$/port: 9090/' config.yaml
git add config.yaml
as "Oleg" oleg "Change port to 9090"

# тем временем в main: другой порт
git switch -q main
sed -i 's/^port: 8080$/port: 8000/' config.yaml
git add config.yaml
as "Anna" anna "Set port to 8000"

echo "Готово: создан репозиторий shop-repo/ (ветки: main, change-port)."
echo "Дальше: cd shop-repo"
