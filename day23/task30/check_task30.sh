#!/bin/bash
# Проверка Задачи 30. Запуск из папки задачи:
#   bash check_task30.sh      — всё
#   bash check_task30.sh 3    — только шаг 3 (и так же 1…6)
# run_tests.sh проверяется во временной папке: там свой «disk_v3.py» и свои тесты,
# одно имя файла теста — с пробелом. wait_ready.sh ждёт временный файл в папке с пробелом.
# Твои файлы проверка не меняет.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0
HERE=$(pwd)

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# need_script файл — файл на месте, с правом x, шебанг, переводы строк LF
need_script() {
    if [ ! -f "$1" ]; then bad "нет файла $1 в папке задачи"; return 1; fi
    if [ ! -x "$1" ]; then bad "$1 не запускается как программа — нет права x (урок 11, часть 1)"; return 1; fi
    if [ "$(head -n 1 "$1")" != "#!/bin/bash" ]; then bad "$1: первая строка не #!/bin/bash"; return 1; fi
    if grep -q $'\r' "$1"; then bad "$1: Windows-переводы строк (^M) — в VS Code внизу справа CRLF → LF"; return 1; fi
    return 0
}

# --- run_tests.sh: временная папка со своим disk_v3.py ---
# Ненастоящий disk_v3.py: читает первую строку ввода и выходит с этим кодом.
# Ещё он печатает строки в stdout и stderr — их на экране быть не должно.
make_lab() {
    LAB="$TMP/lab"
    rm -rf "$LAB"
    mkdir -p "$LAB/tests"
    cp "$HERE/run_tests.sh" "$LAB/"
    cat > "$LAB/disk_v3.py" <<'PY'
import sys
first = sys.stdin.readline().strip()
print("вывод проверяемого скрипта")
print("и в stderr", file=sys.stderr)
sys.exit(int(first))
PY
}

# run_lab → OUT (stdout и stderr вместе), CODE
run_lab() {
    OUT=$(cd "$LAB" && timeout 20 ./run_tests.sh 2>&1 </dev/null)
    CODE=$?
}

if run_step 1; then
    echo "Шаг 1. Перебор файлов тестов"
    if need_script run_tests.sh; then
        ok "run_tests.sh есть, запускается, шебанг и LF на месте"
        make_lab
        printf '0\n0\n' > "$LAB/tests/alpha.txt"
        printf '1\n1\n' > "$LAB/tests/beta test.txt"
        printf '2\n2\n' > "$LAB/tests/gamma.txt"
        printf 'не тест\n' > "$LAB/tests/notes.md"
        run_lab
        for f in "tests/alpha.txt" "tests/beta test.txt" "tests/gamma.txt"; do
            if echo "$OUT" | grep -qF "$f"; then ok "в выводе есть $f"
            else bad "в выводе нет строки с $f — цикл перебирает tests/*.txt? (часть 2)"; fi
        done
        if echo "$OUT" | grep -qF "notes.md"; then bad "в выводе есть notes.md — перебирать нужно только файлы .txt"
        else ok "notes.md (не .txt) пропущен"; fi
        if grep -q "test1_mixed" run_tests.sh; then bad "в run_tests.sh имена тестов написаны вручную — нужен шаблон tests/*.txt"
        else ok "имена тестов не написаны вручную"; fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. Каждый тест: ждём код → получаем код"
    if need_script run_tests.sh; then
        make_lab
        printf '0\n0\n' > "$LAB/tests/a_ok.txt"
        printf '1\n1\n' > "$LAB/tests/b with space.txt"
        printf '2\n0\n' > "$LAB/tests/c_fail.txt"
        run_lab
        line=$(echo "$OUT" | grep -F "tests/a_ok.txt")
        if [ "$line" == "PASS tests/a_ok.txt: код 0" ]; then ok "«$line»"
        else bad "для a_ok.txt ждём «PASS tests/a_ok.txt: код 0», сейчас: «$line»"; fi
        line=$(echo "$OUT" | grep -F "tests/b with space.txt")
        if [ "$line" == "PASS tests/b with space.txt: код 1" ]; then ok "«$line» — файл с пробелом в имени"
        else bad "для файла с пробелом ждём «PASS tests/b with space.txt: код 1», сейчас: «$line» — переменная в кавычках? (урок 11, часть 2)"; fi
        line=$(echo "$OUT" | grep -F "tests/c_fail.txt")
        if [ "$line" == "FAIL tests/c_fail.txt: ждали 2, получили 0" ]; then ok "«$line»"
        else bad "для c_fail.txt ждём «FAIL tests/c_fail.txt: ждали 2, получили 0», сейчас: «$line». Если там PASS — в скрипт ушла и первая строка файла (нужно tail -n +2)"; fi
        if echo "$OUT" | grep -q "вывод проверяемого\|и в stderr"; then bad "на экран попал вывод disk_v3.py — его нужно выкинуть (stdout и stderr)"
        else ok "вывода disk_v3.py на экране нет"; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Счётчики и код возврата"
    if need_script run_tests.sh; then
        make_lab
        printf '0\n0\n' > "$LAB/tests/a.txt"
        printf '1\n1\n' > "$LAB/tests/b b.txt"
        printf '3\n3\n' > "$LAB/tests/c.txt"
        run_lab
        last=$(echo "$OUT" | tail -n 1)
        if [ "$last" == "Пройдено: 3 из 3, провалено: 0" ]; then ok "все прошли — «$last»"
        else bad "все 3 теста прошли — последняя строка должна быть «Пройдено: 3 из 3, провалено: 0», сейчас: «$last»"; fi
        if [ "$CODE" -eq 0 ]; then ok "все прошли — код 0"
        else bad "все прошли — код $CODE, а ждём 0"; fi
        printf '2\n0\n' > "$LAB/tests/d.txt"
        printf '0\n1\n' > "$LAB/tests/e.txt"
        run_lab
        last=$(echo "$OUT" | tail -n 1)
        if [ "$last" == "Пройдено: 3 из 5, провалено: 2" ]; then ok "2 упали — «$last»"
        else bad "из 5 тестов 2 упали — ждём «Пройдено: 3 из 5, провалено: 2», сейчас: «$last»"; fi
        if [ "$CODE" -eq 1 ]; then ok "есть упавшие — код 1"
        else bad "есть упавшие — код $CODE, а ждём 1"; fi
    fi
    echo "  Настоящие тесты disk_v3.py:"
    if [ -x run_tests.sh ] && [ -f disk_v3.py ]; then
        OUT=$(timeout 30 ./run_tests.sh 2>&1 </dev/null); CODE=$?
        last=$(echo "$OUT" | tail -n 1)
        if [ "$last" == "Пройдено: 7 из 7, провалено: 0" ] && [ "$CODE" -eq 0 ]; then ok "./run_tests.sh — «$last», код 0"
        else bad "./run_tests.sh в папке задачи — ждём «Пройдено: 7 из 7, провалено: 0» и код 0, сейчас: «$last», код $CODE. Лишний файл в tests/?"; fi
    else
        bad "нет run_tests.sh с правом x или disk_v3.py в папке задачи"
    fi
fi

# --- wait_ready.sh ---
W_DIR="$TMP/shop ready"
mkdir -p "$W_DIR"
W_FILE="$W_DIR/shop.ready"

# run_wait аргументы… → OUT, ERR, CODE, MS (сколько миллисекунд шёл)
# Больше 12 с — останавливаем: это бесконечный цикл.
run_wait() {
    local start
    start=$(date +%s%N)
    OUT=$(timeout 12 ./wait_ready.sh "$@" 2>"$TMP/stderr" </dev/null)
    CODE=$?
    ERR=$(cat "$TMP/stderr")
    MS=$(( ($(date +%s%N) - start) / 1000000 ))
    if [ "$CODE" -eq 124 ]; then
        bad "wait_ready.sh не закончился за 12 с — бесконечный цикл: счётчик попыток увеличивается? (часть 5)"
    fi
}

if run_step 4; then
    echo "Шаг 4. wait_ready.sh — ждём файл"
    if need_script wait_ready.sh; then
        ok "wait_ready.sh есть, запускается, шебанг и LF на месте"
        touch "$W_FILE"
        run_wait "$W_FILE" 5
        first=$(echo "$OUT" | head -n 1)
        if [ "$CODE" -eq 0 ] && [ "$first" == "Готово: $W_FILE есть, попытка 1 из 5" ]; then ok "файл уже есть — сразу «Готово…, попытка 1 из 5», код 0"
        else bad "файл уже есть — ждём первой строкой «Готово: $W_FILE есть, попытка 1 из 5» и код 0. Сейчас: «$first», код $CODE"; fi
        if [ "$MS" -lt 800 ]; then ok "файл уже есть — без лишнего ожидания"
        else bad "файл уже есть, а скрипт ждал $MS мс — сначала проверка файла, потом sleep"; fi
        rm -f "$W_FILE"
        ( sleep 2.5; touch "$W_FILE" ) &
        run_wait "$W_FILE" 8
        wait
        lines=$(echo "$OUT" | grep -c "^Жду ")
        last=$(echo "$OUT" | tail -n 1)
        if echo "$OUT" | grep -qxF "Жду $W_FILE: попытка 1 из 8" && echo "$OUT" | grep -qxF "Жду $W_FILE: попытка 2 из 8"; then ok "пока файла нет — «Жду …: попытка 1 из 8», «… 2 из 8»"
        else bad "пока файла нет — ждём строки «Жду $W_FILE: попытка 1 из 8», потом «… 2 из 8». Сейчас первая: «$(echo "$OUT" | head -n 1)»"; fi
        if [ "$CODE" -eq 0 ] && echo "$last" | grep -qx "Готово: .* есть, попытка [34] из 8"; then ok "файл появился через 2,5 с — «$last», код 0"
        else bad "файл появился через 2,5 с — ждём последней строкой «Готово: … есть, попытка 3 из 8» (или 4) и код 0. Сейчас: «$last», код $CODE"; fi
        if [ "$lines" -ge 2 ] && [ "$lines" -le 3 ]; then ok "ожидание по 1 с: строк «Жду» — $lines"
        else bad "строк «Жду» — $lines, а за 2,5 с должно быть 2–3. Есть sleep 1 и счётчик +1?"; fi
        rm -f "$W_FILE"
    fi
fi

if run_step 5; then
    echo "Шаг 5. wait_ready.sh — не дождались и неверный запуск"
    if need_script wait_ready.sh; then
        rm -f "$W_FILE"
        run_wait "$W_FILE" 2
        n=$(echo "$OUT" | grep -c "^Жду ")
        if [ "$CODE" -eq 1 ]; then ok "не дождались — код 1"
        else bad "не дождались — код $CODE, а ждём 1"; fi
        if [ "$n" -eq 2 ] && [ "$MS" -ge 1800 ] && [ "$MS" -le 3500 ]; then ok "2 попытки — 2 строки «Жду», ≈ 2 с"
        else bad "2 попытки — ждём 2 строки «Жду» и ≈ 2 с. Сейчас строк $n, $MS мс"; fi
        if [ "$ERR" == "ОШИБКА: $W_FILE не появился за 2 с" ]; then ok "в stderr: «$ERR»"
        else bad "в stderr ждём «ОШИБКА: $W_FILE не появился за 2 с», сейчас: «$(echo "$ERR" | head -n 1)»"; fi
        if echo "$OUT" | grep -q "ОШИБКА"; then bad "ОШИБКА попала в stdout, а нужна в stderr"; fi
        for args in "none" "one"; do
            if [ "$args" == "none" ]; then run_wait; what="без аргументов"; else run_wait "$W_FILE"; what="с одним аргументом"; fi
            if [ "$CODE" -eq 2 ] && echo "$ERR" | grep -q "^ОШИБКА: нужно 2 аргумента"; then ok "$what — ОШИБКА в stderr, код 2"
            else bad "$what — ждём в stderr «ОШИБКА: нужно 2 аргумента…» и код 2. Сейчас код $CODE, stderr: «$(echo "$ERR" | head -n 1)»"; fi
            if [ "$MS" -gt 800 ]; then bad "$what — скрипт ждал $MS мс, а должен выйти сразу"; fi
        done
    fi
fi

if run_step 6; then
    echo "Шаг 6. Git и README"
    for f in run_tests.sh wait_ready.sh disk_v3.py check_task30.sh tests/test1_mixed.txt; do
        if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then ok "$f в Git"; else bad "$f не добавлен в Git"; fi
    done
    for f in run_tests.sh wait_ready.sh; do
        mode=$(git ls-files -s "$f" 2>/dev/null | cut -d' ' -f1)
        if [ "$mode" == "100755" ]; then ok "$f в Git с правом x (100755)"
        else bad "$f в Git без права x (${mode:-нет}) — chmod +x, потом add + commit"; fi
    done
    readme="$(git rev-parse --show-toplevel 2>/dev/null)/README.md"
    if grep -q '`day23/`' "$readme" 2>/dev/null; then ok "в README есть строка day23/"
    else bad "в README нет строки для day23/"; fi
    if grep -q '^- \[x\] Bash scripting' "$readme" 2>/dev/null; then ok "в Progress отмечен Bash scripting"
    else bad "в Progress не отмечен пункт Bash scripting"; fi
fi

echo
echo "Пройдено: $PASS, ошибок: $FAIL"
if [ "$FAIL" -eq 0 ]; then echo "Все проверки прошли ✅"; else exit 1; fi
