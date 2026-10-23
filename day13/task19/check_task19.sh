#!/bin/bash
# Проверка Задачи 19. Запуск из папки задачи:
#   bash check_task19.sh      — всё
#   bash check_task19.sh 2    — только шаг 2 (и так же 1, 3, 4, 5, 6)
# Смотрит историю и файлы в shop-repo/. Сам ничего в shop-repo/ не меняет.
# Если шаги 1–5 пройдены, записывает result.txt — снимок истории shop-repo
# для проверки на GitHub (shop-repo/ в Git не попадает).

cd "$(dirname "$0")" || exit 1
here=$(pwd)
R="$here/shop-repo"
STEP="${1:-all}"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
g()   { git -C "$R" "$@"; }

if [ ! -d "$R/.git" ]; then
    echo "Нет папки shop-repo/ — сначала: bash setup.sh"
    exit 1
fi

has_branch()  { g show-ref --verify -q "refs/heads/$1"; }
merging()     { [ -f "$R/.git/MERGE_HEAD" ]; }
clean()       { [ -z "$(g status --porcelain)" ]; }
# коммит коллеги из ветки change-port и последний коммит main из setup.sh
port_commit() { g log --all --format=%H --grep='^Change port to 9090$' | tail -n 1; }
base_commit() { g log --all --format=%H --grep='^Set port to 8000$' | tail -n 1; }
# твой коммит, который добавил строку healthcheck
hc_commit()   { g log --all --format=%H -G'^healthcheck: /health$' -- config.yaml | tail -n 1; }
# содержимое файла без пустых строк и пробелов в конце строк
norm()        { sed -e 's/[[:space:]]*$//' | grep -v '^$'; }

# ---------- шаг 1 ----------
step1() {
    if has_branch add-healthcheck || g reflog | grep -q 'moving from main to add-healthcheck'; then
        ok "ветка add-healthcheck создана, ты на неё переходил"
    else
        bad "нет ветки add-healthcheck (имя точно такое? проверь: git branch)"
    fi
}

# ---------- шаг 2 ----------
step2() {
    local hc
    hc=$(hc_commit)
    if [ -z "$hc" ]; then
        bad "нет коммита со строкой «healthcheck: /health» в config.yaml"
        return
    fi
    ok "есть коммит со строкой healthcheck: $(g log -1 --format='%h %s' "$hc")"
    if [ "$(g rev-parse "$hc^")" == "$(base_commit)" ]; then
        ok "коммит сделан поверх «Set port to 8000» (ветка от main)"
    else
        bad "коммит сделан не от последнего коммита main"
    fi
    if [ -z "$(g diff --numstat "$hc^" "$hc" | grep -v $'^[0-9]*\t0\tconfig.yaml$')" ]; then
        ok "в коммите только добавлена строка в config.yaml"
    else
        bad "в коммите лишние изменения:"; g diff --stat "$hc^" "$hc" | sed 's/^/        /'
    fi
    if has_branch add-healthcheck; then
        if [ "$(g rev-parse add-healthcheck)" == "$hc" ]; then ok "коммит лежит в ветке add-healthcheck"
        else bad "последний коммит ветки add-healthcheck — не коммит с healthcheck"; fi
        if g merge-base --is-ancestor "$hc" main && ! g reflog show main | grep -q 'merge add-healthcheck'; then
            bad "коммит попал прямо в main — коммитить надо, стоя в ветке add-healthcheck (git branch покажет, где ты)"
        fi
    fi
}

# ---------- шаг 3 ----------
step3() {
    if g reflog show main | grep -q 'merge add-healthcheck: Fast-forward'; then
        ok "add-healthcheck влита в main (fast-forward)"
    else
        bad "в истории main нет «merge add-healthcheck: Fast-forward» — ты в main делал git merge add-healthcheck?"
    fi
    if has_branch add-healthcheck; then bad "ветка add-healthcheck ещё есть — после слияния её удаляют"
    else ok "ветка add-healthcheck удалена"; fi
}

# ---------- шаг 4 ----------
step4() {
    local a="$here/answers.txt"
    if [ ! -f "$a" ]; then
        bad "нет файла answers.txt"
    else
        local l1 l2 l3
        l1=$(sed -n 1p "$a" | tr -d '[:space:]')
        l2=$(sed -n 2p "$a" | tr -d '[:space:]')
        l3=$(sed -n 3p "$a" | tr -d '[:space:]')
        [ "$l1" == "config.yaml" ] && ok "answers.txt, строка 1 — файл с конфликтом" || bad "answers.txt, строка 1: файл с конфликтом — не «$l1»"
        [ "$l2" == "8000" ]        && ok "answers.txt, строка 2 — порт в main (HEAD)"  || bad "answers.txt, строка 2: порт в main — не «$l2»"
        [ "$l3" == "9090" ]        && ok "answers.txt, строка 3 — порт в change-port" || bad "answers.txt, строка 3: порт в change-port — не «$l3»"
    fi
    if g reflog | grep -q 'reset: moving to HEAD'; then ok "слияние отменялось через git merge --abort"
    else bad "не вижу git merge --abort"; fi
    # если шаг 5 ещё не сделан — после --abort всё должно быть чисто
    if ! g merge-base --is-ancestor "$(port_commit)" main 2>/dev/null; then
        if merging; then bad "слияние всё ещё идёт — git merge --abort"
        elif ! clean; then bad "в shop-repo есть незакоммиченные изменения (git status)"
        else ok "после отмены всё чисто: слияния нет, git status пустой"; fi
    fi
}

# ---------- шаг 5 ----------
step5() {
    local pc m want got
    pc=$(port_commit)
    if merging; then bad "слияние не закончено: git add config.yaml, потом git commit"; return; fi
    m=$(g rev-list --merges --first-parent main | while read -r c; do
            [ "$(g rev-parse "$c^2")" == "$pc" ] && echo "$c"; done | head -n 1)
    if [ -n "$m" ]; then ok "в main есть merge-коммит с веткой change-port: $(g log -1 --format='%h %s' "$m")"
    else bad "в main нет merge-коммита, который влил change-port"; return; fi
    if g show main:config.yaml | grep -qE '^(<<<<<<<|=======|>>>>>>>)'; then
        bad "в config.yaml остались маркеры конфликта (<<<<<<< ======= >>>>>>>)"
    else ok "маркеров конфликта нет"; fi
    want=$(g show "$(base_commit)":config.yaml | sed 's/^port: 8000$/port: 9090/'; echo 'healthcheck: /health')
    got=$(g show main:config.yaml)
    if [ "$(echo "$want" | norm)" == "$(echo "$got" | norm)" ]; then
        ok "config.yaml в main: port 9090, healthcheck на месте, остальное не тронуто"
    else
        bad "config.yaml в main не такой, как нужно. Разница (− нужно, + у тебя):"
        diff <(echo "$want" | norm) <(echo "$got" | norm) | grep '^[<>]' | sed -e 's/^</−/' -e 's/^>/+/' -e 's/^/        /'
    fi
    if has_branch change-port; then bad "ветка change-port ещё есть — после слияния её удаляют"
    else ok "ветка change-port удалена"; fi
    if [ "$(g branch --show-current)" == "main" ] && clean; then ok "ты в main, git status пустой"
    else bad "в shop-repo надо стоять в main с пустым git status"; fi
}

# ---------- шаг 6 ----------
step6() {
    local f missing=""
    for f in .gitignore setup.sh check_task19.sh answers.txt result.txt; do
        if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then missing="$missing $f"; fi
    done
    if [ -z "$missing" ]; then ok "файлы задачи добавлены в Git"; else bad "не добавлены в Git:$missing"; fi
    if git check-ignore -q shop-repo/config.yaml 2>/dev/null; then ok "shop-repo/ не попадёт в Git (.gitignore)"
    else bad "shop-repo/ не в .gitignore — учебный репозиторий попадёт в Git"; fi
}

run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

if run_step 1; then echo "Шаг 1. Новая ветка";              step1; fi
if run_step 2; then echo "Шаг 2. Коммит в ветке";           step2; fi
if run_step 3; then echo "Шаг 3. Fast-forward и удаление";  step3; fi
if run_step 4; then echo "Шаг 4. Конфликт и --abort";       step4; fi
if run_step 5; then echo "Шаг 5. Решить конфликт";          step5; fi

# снимок для проверки на GitHub
if [ "$STEP" == "all" ] && [ "$FAIL" -eq 0 ]; then
    {
        echo "# git log --oneline --graph --all"
        g log --graph --all --format='%s (%an)'
        echo
        echo "# config.yaml в main"
        g show main:config.yaml
    } > "$here/result.txt"
    echo "  📝 шаги 1–5 пройдены — записан result.txt"
fi

if run_step 6; then echo "Шаг 6. Git (devops-learning)";    step6; fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
