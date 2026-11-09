#!/bin/bash
# Проверка Задачи 31. Запуск НА СЕРВЕРЕ, из папки задачи:
#   bash check_task31.sh      — всё
#   bash check_task31.sh 3    — только шаг 3 (и так же 1…6)
# Числа из answers.txt сравниваются с тем, что сейчас показывает сама машина.
# temps.sh проверяется дважды: на настоящих датчиках и на ненастоящей папке датчиков
# (её имя — с пробелом). Твои файлы проверка не меняет.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0
THERMAL="${THERMAL_DIR:-/sys/class/thermal}"   # THERMAL_DIR — только для отладки проверки

ok()   { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
note() { echo "  ℹ️  $1"; }
run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

TMP=$(mktemp -d)
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

if [ "$(hostname)" != "mindserver" ]; then
    echo "⚠️  Проверка запущена не на mindserver ($(hostname)). Числа сравниваются с ЭТОЙ машиной — запускай на сервере."
fi

# --- answers.txt ---
# answer ключ → значение строки «ключ: значение» (пробелы по краям убраны)
answer() {
    [ -f answers.txt ] || return 0
    grep -m 1 "^$1:" answers.txt | cut -d: -f2- | tr -d ' \r'
}
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }
is_dec() { [[ "$1" =~ ^[0-9]+\.[0-9]{2}$ ]]; }
# вещественные числа сравнивает awk: fcmp "1.5 >= 2"
fcmp() { awk "BEGIN { exit !($1) }"; }

need_answers() {
    if [ ! -f answers.txt ]; then bad "нет файла answers.txt в папке задачи"; return 1; fi
    if grep -q $'\r' answers.txt; then note "в answers.txt Windows-переводы строк (CRLF) — проверка их пропускает, но лучше LF (VS Code, внизу справа)"; fi
    return 0
}

meminfo_kb() { grep -m 1 "^$1:" /proc/meminfo | tr -s ' ' | cut -d' ' -f2; }
zone_temp()  { cat "$1/temp" 2>/dev/null; }

# --- temps.sh ---
need_script() {
    if [ ! -f "$1" ]; then bad "нет файла $1 в папке задачи"; return 1; fi
    if [ ! -x "$1" ]; then bad "$1 не запускается как программа — нет права x (урок 11, часть 1)"; return 1; fi
    if [ "$(head -n 1 "$1")" != "#!/bin/bash" ]; then bad "$1: первая строка не #!/bin/bash"; return 1; fi
    if grep -q $'\r' "$1"; then bad "$1: Windows-переводы строк (^M) — в VS Code внизу справа CRLF → LF"; return 1; fi
    if ! grep -q '^dir=' "$1"; then bad "$1: нет строки, которая начинается с dir= (путь к папке датчиков — в переменной dir)"; return 1; fi
    if [ "$(grep -c '^dir=' "$1")" -ne 1 ]; then bad "$1: строка dir= должна быть одна"; return 1; fi
    return 0
}

# run_temps папка → OUT, ERR, CODE. Запускает копию temps.sh, где dir= указывает на папку.
run_temps() {
    local copy="$TMP/temps_copy.sh"
    sed "s|^dir=.*|dir=\"$1\"|" temps.sh > "$copy"
    chmod +x "$copy"
    timeout 10 "$copy" > "$TMP/out" 2> "$TMP/err" < /dev/null
    CODE=$?
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
}

# fake_zone папка номер тип миллиградусы — ненастоящий датчик
fake_zone() {
    mkdir -p "$1/thermal_zone$2"
    echo "$3" > "$1/thermal_zone$2/type"
    echo "$4" > "$1/thermal_zone$2/temp"
}

# ---------------------------------------------------------------
if run_step 1; then
    echo "Шаг 1. Память"
    if need_answers; then
        total=$(answer mem_total_kb); avail=$(answer mem_available_kb); pct=$(answer mem_available_pct)
        real_total=$(meminfo_kb MemTotal); real_avail=$(meminfo_kb MemAvailable)
        if ! is_int "$total"; then bad "mem_total_kb: ждём только число из строки MemTotal, без kB, сейчас: «$total»"
        elif [ "$total" -ne "$real_total" ]; then bad "mem_total_kb: $total, а в /proc/meminfo MemTotal = $real_total"
        else ok "mem_total_kb: $total — совпадает с MemTotal"; fi
        if ! is_int "$avail"; then bad "mem_available_kb: ждём только число из строки MemAvailable, без kB, сейчас: «$avail»"
        elif [ "$avail" -le 0 ] || [ "$avail" -gt "$real_total" ]; then bad "mem_available_kb: $avail — должно быть больше 0 и не больше MemTotal"
        else
            diff=$((avail - real_avail)); diff=${diff#-}
            if [ $((diff * 100 / real_total)) -gt 15 ]; then
                bad "mem_available_kb: $avail, а сейчас MemAvailable = $real_avail — разница больше 15% памяти. Не та строка (MemFree?) или прочитай заново"
            else ok "mem_available_kb: $avail (сейчас MemAvailable = $real_avail, память живая — небольшая разница нормальна)"; fi
        fi
        if ! is_int "$pct"; then bad "mem_available_pct: ждём целое число процентов (без знака %), сейчас: «$pct»"
        elif is_int "$total" && is_int "$avail" && [ "$total" -gt 0 ]; then
            want=$((avail * 100 / total))
            d=$((pct - want)); d=${d#-}
            if [ "$d" -le 1 ]; then ok "mem_available_pct: $pct% — посчитано верно"
            else bad "mem_available_pct: $pct, а из твоих чисел выходит $want (available × 100 / total)"; fi
        fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. Процессоры и нагрузка"
    if need_answers; then
        cores=$(answer cores); load1=$(answer load_1)
        if ! is_int "$cores"; then bad "cores: ждём целое число, сейчас: «$cores»"
        elif [ "$cores" -ne "$(nproc)" ]; then bad "cores: $cores, а nproc показывает $(nproc)"
        else ok "cores: $cores — совпадает с nproc"; fi
        if ! is_dec "$load1"; then bad "load_1: ждём число как в uptime, с точкой и двумя знаками (например 0.27), сейчас: «$load1»"
        elif fcmp "$load1 > $(nproc) * 4"; then bad "load_1: $load1 — подозрительно много для сервера в покое. Это первое из трёх чисел?"
        else ok "load_1: $load1"; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Датчик процессора"
    if need_answers; then
        zone=$(answer cpu_zone); t=$(answer cpu_temp)
        pkg=""
        for z in "$THERMAL"/thermal_zone*; do
            if [ -d "$z" ] && [ "$(cat "$z/type" 2>/dev/null)" = "x86_pkg_temp" ]; then pkg=$(basename "$z"); fi
        done
        if ! [[ "$zone" =~ ^thermal_zone[0-9]+$ ]]; then bad "cpu_zone: ждём имя папки вида thermal_zoneN, сейчас: «$zone»"
        elif [ ! -d "$THERMAL/$zone" ]; then bad "cpu_zone: папки $THERMAL/$zone нет"
        elif [ -n "$pkg" ] && [ "$zone" != "$pkg" ]; then bad "cpu_zone: $zone — это $(cat "$THERMAL/$zone/type"). Датчик процессора Intel — x86_pkg_temp (урок 13, часть 4)"
        else
            ok "cpu_zone: $zone ($(cat "$THERMAL/$zone/type"))"
            if [ -z "$pkg" ]; then note "x86_pkg_temp на этой машине нет — напиши Claude, какой датчик выбрал и почему"; fi
        fi
        if ! is_int "$t"; then bad "cpu_temp: ждём целое число градусов, сейчас: «$t»"
        elif [ "$t" -gt 120 ]; then bad "cpu_temp: $t — это миллиградусы? Раздели на 1000"
        elif [ "$t" -lt 15 ]; then bad "cpu_temp: $t °C — слишком холодно для работающего процессора"
        elif [[ "$zone" =~ ^thermal_zone[0-9]+$ ]] && [ -d "$THERMAL/$zone" ]; then
            live=$(zone_temp "$THERMAL/$zone")
            if is_int "${live#-}"; then
                d=$((t - live / 1000)); d=${d#-}
                if [ "$d" -gt 20 ]; then bad "cpu_temp: $t °C, а сейчас датчик показывает $((live / 1000)) °C — проверь"
                else ok "cpu_temp: $t °C (сейчас $((live / 1000)) °C)"; fi
            else ok "cpu_temp: $t °C"; fi
        fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. temps.sh — все датчики в градусах"
    if need_script temps.sh; then
        ok "temps.sh есть, запускается, шебанг, LF и dir= на месте"
        F="$TMP/fake thermal"
        mkdir -p "$F/cooling_device0"; echo "Processor" > "$F/cooling_device0/type"
        fake_zone "$F" 0 acpitz 45000
        fake_zone "$F" 1 x86_pkg_temp 52500
        run_temps "$F"
        if [ "$OUT" == "acpitz: 45 °C"$'\n'"x86_pkg_temp: 52 °C" ]; then ok "ненастоящие датчики: «acpitz: 45 °C», «x86_pkg_temp: 52 °C»"
        else bad "на ненастоящих датчиках (45000 и 52500) ждём две строки «acpitz: 45 °C» и «x86_pkg_temp: 52 °C», сейчас: «$OUT»$( [ -n "$ERR" ] && echo " | stderr: «$ERR»"). Имя папки с пробелом: \"\$dir\"/thermal_zone*"; fi
        if echo "$OUT" | grep -q "Processor"; then bad "в вывод попал cooling_device0 — это не датчик, перебирать нужно только thermal_zone*"; fi
        # настоящие датчики
        zones=0
        for z in "$THERMAL"/thermal_zone*; do [ -d "$z" ] && zones=$((zones + 1)); done
        if [ "$zones" -eq 0 ]; then
            bad "на этой машине нет датчиков в $THERMAL — шаг 4 проверяется на сервере"
        else
            run_temps "$THERMAL"
            n=0; good=0; skipped=0
            for z in "$THERMAL"/thermal_zone*; do
                [ -d "$z" ] || continue
                n=$((n + 1))
                name=$(cat "$z/type")
                line=$(echo "$OUT" | sed -n "${n}p")
                live=$(zone_temp "$z")
                if [ -z "$live" ]; then skipped=$((skipped + 1)); continue; fi
                got=$(echo "$line" | sed -n "s/^$name: \(-\?[0-9]\+\) °C$/\1/p")
                if [ -n "$got" ] && [ $(( (got - live / 1000) * (got - live / 1000) )) -le 9 ]; then good=$((good + 1))
                else bad "строка $n: ждём «$name: $((live / 1000)) °C» (±3), сейчас: «$line»"; fi
            done
            if [ "$good" -eq $((n - skipped)) ]; then ok "настоящие датчики ($n шт.): тип и градусы совпадают"; fi
            if [ "$skipped" -gt 0 ]; then note "датчиков, которые сейчас не отдают температуру: $skipped — их строки проверяются в шаге 5"; fi
        fi
    fi
fi

if run_step 5; then
    echo "Шаг 5. temps.sh — нет данных и нет датчиков"
    if need_script temps.sh; then
        F="$TMP/fake broken"
        fake_zone "$F" 0 acpitz 41000
        fake_zone "$F" 1 iwlwifi_1 38000
        if [ "$(id -u)" -eq 0 ]; then
            note "проверка запущена от root — для root нечитаемых файлов нет, этот случай пропущен"
        else
            chmod 000 "$F/thermal_zone1/temp"
            run_temps "$F"
            if [ "$OUT" == "acpitz: 41 °C"$'\n'"iwlwifi_1: нет данных" ]; then ok "датчик без данных: «iwlwifi_1: нет данных»"
            else bad "датчик, у которого не читается temp: ждём «acpitz: 41 °C» и «iwlwifi_1: нет данных», сейчас: «$OUT»"; fi
            if [ -z "$ERR" ]; then ok "ошибки cat на экран не попали"
            else bad "в stderr: «$ERR» — ошибку cat нужно выкинуть (2>/dev/null, урок 07)"; fi
            if [ "$CODE" -eq 0 ]; then ok "код 0 — один датчик без данных не ошибка"
            else bad "код $CODE, а ждём 0: один датчик без данных — не ошибка скрипта"; fi
        fi
        E="$TMP/empty thermal"
        mkdir -p "$E"
        run_temps "$E"
        want="ОШИБКА: нет датчиков температуры в $E"
        if [ "$CODE" -eq 1 ]; then ok "нет датчиков — код 1"
        else bad "нет ни одного датчика — код $CODE, а ждём 1"; fi
        if [ "$ERR" == "$want" ]; then ok "нет датчиков — в stderr «ОШИБКА: нет датчиков температуры в …»"
        else bad "нет датчиков — в stderr ждём «$want», сейчас: «$ERR»"; fi
        if [ -z "$OUT" ]; then ok "нет датчиков — stdout пустой"
        else bad "нет датчиков — в stdout ничего не должно быть, сейчас: «$OUT»"; fi
        zones=0
        for z in "$THERMAL"/thermal_zone*; do [ -d "$z" ] && zones=$((zones + 1)); done
        if [ "$zones" -gt 0 ]; then
            run_temps "$THERMAL"
            lines=$(echo "$OUT" | grep -c .)
            if [ "$CODE" -eq 0 ] && [ "$lines" -eq "$zones" ] && [ -z "$ERR" ]; then ok "настоящие датчики: $zones строк, код 0, stderr пустой"
            else bad "на настоящих датчиках ждём $zones строк, код 0 и пустой stderr; сейчас строк $lines, код $CODE, stderr: «$ERR»"; fi
        fi
    fi
fi

if run_step 6; then
    echo "Шаг 6. Git и README"
    for f in answers.txt temps.sh; do
        if git ls-files --error-unmatch "$f" > /dev/null 2>&1; then ok "$f добавлен в Git"
        else bad "$f не добавлен в Git (git add)"; fi
    done
    if git ls-files --error-unmatch load.sh > /dev/null 2>&1; then bad "load.sh ещё в Git — шаг с нагрузкой убран: git rm load.sh"
    else ok "load.sh убран"; fi
    if grep -q '`day24/`' ../../README.md 2>/dev/null; then ok "в README есть строка для day24/"
    else bad "в README (корень репозитория) нет строки для \`day24/\` в таблице Structure"; fi
fi

echo
echo "Итог: ✅ $PASS, ❌ $FAIL"
if [ "$FAIL" -eq 0 ]; then
    if [ "$STEP" == "all" ]; then echo "Все проверки прошли ✅"; else echo "Шаг $STEP пройден ✅"; fi
    exit 0
fi
exit 1
