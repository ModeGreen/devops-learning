#!/bin/bash
# Проверка Задачи 33. Запуск НА СЕРВЕРЕ, из папки задачи:
#   bash check_task33.sh      — всё
#   bash check_task33.sh 2    — только шаг 2 (и так же 1…4)
# Шаг 1: ответы из answers.txt сравниваются с тем, что сервер показывает прямо сейчас
#        (ss и GET-запросы к Navidrome и Syncthing — только чтение, на сервере ничего не меняется).
# Шаги 2–3: check_http.sh запускается на учебном HTTP-сервере, который проверка поднимает
#        на 127.0.0.1 на время проверки (он отвечает нужными кодами), и на настоящих
#        health endpoint Navidrome и Syncthing. Твои файлы проверка не меняет.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
note() { echo "  ℹ️  $1"; }
run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

TMP=$(mktemp -d)
SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; fi
    rm -rf "$TMP"
}
trap cleanup EXIT


# --- answers.txt ---
# answer ключ → значение строки «ключ: значение» (пробелы по краям убраны)
answer() {
    [ -f answers.txt ] || return 0
    grep -m 1 "^$1:" answers.txt | cut -d: -f2- | tr -d ' \r'
}
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

need_answers() {
    if [ ! -f answers.txt ]; then bad "нет файла answers.txt в папке задачи"; return 1; fi
    if grep -q $'\r' answers.txt; then note "в answers.txt Windows-переводы строк (CRLF) — проверка их пропускает, но лучше LF (VS Code, внизу справа)"; fi
    return 0
}

# --- сеть ---
# порт есть среди слушающих TCP-портов?
is_listening() { ss -tln | awk 'NR > 1 {print $4}' | grep -Eq ":$1\$"; }
# код ответа (000 — ответа нет), тело, значение заголовка Location
http_code()     { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1"; }
http_body()     { curl -s --max-time 5 "$1"; }
http_location() { curl -s -i --max-time 5 "$1" | grep -i -m 1 '^location:' | cut -d' ' -f2- | tr -d '\r'; }
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'; }

# Порты из шага 1 — для шагов 2 и 3. Пустые, пока ответ не подтверждён.
NAV_PORT=""
GUI_PORT=""
find_service_ports() {
    local p
    p=$(answer navidrome_port)
    if is_int "$p" && [ "$(http_code "http://localhost:$p/ping")" == "200" ] \
        && [[ "$(http_location "http://localhost:$p/")" == */app/ ]]; then NAV_PORT=$p; fi
    p=$(answer syncthing_gui_port)
    if is_int "$p" && [ "$(http_code "http://localhost:$p/rest/noauth/health")" == "200" ] \
        && [[ "$(http_body "http://localhost:$p/rest/noauth/health")" == *'"OK"'* ]]; then GUI_PORT=$p; fi
}

# Учебный HTTP-сервер на 127.0.0.1: /code/NNN — ответ с кодом NNN, /slow — ответ через 8 секунд;
# заголовок Location — только у 301.
FAKE=""
start_fake() {
    if [ -n "$SERVER_PID" ]; then return 0; fi
    local port
    port=$(free_port)
    cat > "$TMP/fake.py" <<'PY'
import sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(8)
            code = 200
        elif self.path.startswith("/code/"):
            code = int(self.path.split("/")[2])
        else:
            code = 404
        body = b"test page\n"
        try:
            self.send_response(code)
            if code == 301:
                self.send_header("Location", "/code/200")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
    python3 "$TMP/fake.py" "$port" > /dev/null 2>&1 &
    SERVER_PID=$!
    FAKE="http://127.0.0.1:$port"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if [ "$(http_code "$FAKE/code/200")" == "200" ]; then return 0; fi
        sleep 0.5
    done
    bad "не удалось запустить учебный HTTP-сервер проверки (python3) — напиши мне"
    return 1
}

# --- check_http.sh ---
need_script() {
    local f=check_http.sh
    if [ ! -f "$f" ]; then bad "нет файла $f в папке задачи"; return 1; fi
    if [ ! -x "$f" ]; then bad "$f не запускается как программа — нет права x (chmod +x в WSL, коммит, push, pull)"; return 1; fi
    if grep -q $'\r' "$f"; then bad "$f: Windows-переводы строк (^M) — в VS Code внизу справа CRLF → LF"; return 1; fi
    if [ "$(head -n 1 "$f")" != "#!/bin/bash" ]; then bad "$f: первая строка не #!/bin/bash"; return 1; fi
    if [ "$(grep -c '^max_time=' "$f")" -ne 1 ]; then bad "$f: нужна одна строка, которая начинается с max_time= (сколько секунд ждать ответ)"; return 1; fi
    return 0
}

# run_check [аргументы] → OUT, ERR, CODE, MS (сколько миллисекунд шёл скрипт)
SCRIPT=./check_http.sh
run_check() {
    local start
    start=$(date +%s%N)
    timeout 20 "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err" < /dev/null
    CODE=$?
    MS=$(( ($(date +%s%N) - start) / 1000000 ))
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
}

# hint текст — подсказка, но одна и та же только один раз
SHOWN=""
hint() {
    case "$SHOWN" in *"|$1|"*) return ;; esac
    SHOWN="$SHOWN|$1|"
    note "$1"
}

# try URL ждём_вывод ждём_код что_проверяем [подсказка, если не совпало]
try() {
    run_check "$1"
    if [ "$OUT" == "$2" ] && [ "$CODE" -eq "$3" ] && [ -z "$ERR" ]; then
        ok "$4: «$OUT», код $CODE"
        return
    fi
    bad "$4: ждём «$2» и код $3; сейчас: «$OUT», код $CODE${ERR:+, в stderr: «$ERR»}"
    if [ "$CODE" -eq 124 ]; then hint "скрипт не закончился за 20 секунд — что-то ждёт ввода или висит"
    elif [[ "$OUT" == *"test page"* ]]; then hint "в выводе тело страницы — его нужно выбросить: -o /dev/null (урок 14, часть 4)"
    elif [ "$OUT" == "$2" ] && [ "$CODE" -eq "$3" ]; then hint "текст и код верные, но в stderr что-то есть — там должно быть пусто"
    elif [ "$OUT" == "$2" ]; then hint "текст верный, а код выхода нет: OK — 0, CRITICAL — 2"
    elif [[ "$OUT" == *"- HTTP 000" ]]; then hint "HTTP 000 — ответа не было вовсе. Это случай «no response» с кодом выхода curl; код выхода сохраняют сразу следующей строкой после code=\$(curl ...) (урок 12)"
    elif [[ "$OUT" != "OK: $1 - "* && "$OUT" != "CRITICAL: $1 - "* ]]; then hint "формат — буква в букву: «OK: <url> - HTTP <код>» и «CRITICAL: <url> - HTTP <код>» (двоеточие, пробел, дефис с пробелами)"
    elif [ -n "$5" ]; then hint "$5"; fi
}


# ---------------------------------------------------------------
if run_step 1; then
    echo "Шаг 1. Кто слушает и что отвечает"
    if need_answers; then
        # SSH
        p=$(answer ssh_port)
        if ! is_int "$p"; then bad "ssh_port: ждём число, сейчас: «$p»"
        elif ! is_listening "$p"; then bad "ssh_port: порт $p никто не слушает (его нет в ss -tln)"
        else
            banner=$(timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$p && head -c 4 <&3" 2>/dev/null)
            if [ "$banner" == "SSH-" ]; then ok "ssh_port: $p — на нём отвечает SSH"
            elif [ -z "$banner" ] && [ "$(http_code "http://localhost:$p/")" != "000" ]; then bad "ssh_port: на порту $p отвечает HTTP, а не SSH"
            elif [ -z "$banner" ]; then ok "ssh_port: $p — порт слушают"; note "убедиться, что это именно SSH, не вышло (с 127.0.0.1 не подключиться) — не страшно"
            else bad "ssh_port: на порту $p отвечает не SSH"; fi
        fi

        # Navidrome
        np=$(answer navidrome_port)
        nav_ok=0
        if ! is_int "$np"; then bad "navidrome_port: ждём число, сейчас: «$np»"
        else
            code=$(http_code "http://localhost:$np/ping")
            loc=$(http_location "http://localhost:$np/")
            if [ "$code" == "000" ]; then
                bad "navidrome_port: на порту $np по HTTP никто не отвечает. Это левый номер у стрелки в docker ps? Контейнер работает (STATUS Up)?"
            elif [ "$code" != "200" ]; then
                bad "navidrome_port: на порту $np адрес /ping отвечает $code, а у Navidrome там 200 — похоже, это не Navidrome"
            elif [[ "$loc" != */app/ ]]; then
                bad "navidrome_port: на порту $np корень / перенаправляет не туда, куда Navidrome (Location: «$loc») — похоже, это не Navidrome"
            else
                nav_ok=1
                ok "navidrome_port: $np — отвечает Navidrome"
                if ! is_listening "$np"; then note "порта $np нет в ss -tln — Docker пробрасывает его без docker-proxy. Так бывает, ответ засчитан"; fi
            fi
        fi

        # Syncthing GUI
        sp=$(answer syncthing_gui_port)
        if ! is_int "$sp"; then bad "syncthing_gui_port: ждём число, сейчас: «$sp»"
        else
            code=$(http_code "http://localhost:$sp/rest/noauth/health")
            body=$(http_body "http://localhost:$sp/rest/noauth/health")
            if [ "$code" == "000" ]; then
                bad "syncthing_gui_port: на порту $sp по HTTP никто не отвечает. Порт синхронизации говорит не по HTTP — нужен порт GUI"
            elif [ "$code" == "200" ] && [[ "$body" == *'"OK"'* ]]; then
                ok "syncthing_gui_port: $sp — отвечает GUI Syncthing (/rest/noauth/health → OK)"
            elif [[ "$code" == 3* ]]; then
                bad "syncthing_gui_port: на порту $sp ответ $code (перенаправление) — похоже, это не GUI Syncthing. Если GUI у тебя открывается по https://, напиши мне"
            else
                bad "syncthing_gui_port: на порту $sp адрес /rest/noauth/health отвечает $code — похоже, это не GUI Syncthing"
            fi
        fi

        # Как Navidrome отвечает на корень
        rc=$(answer navidrome_root_code)
        rl=$(answer navidrome_location)
        if [ "$nav_ok" -eq 1 ]; then
            live_code=$(http_code "http://localhost:$np/")
            live_loc=$(http_location "http://localhost:$np/")
            if ! is_int "$rc"; then bad "navidrome_root_code: ждём число — код из первой строки ответа, сейчас: «$rc»"
            elif [ "$rc" != "$live_code" ]; then bad "navidrome_root_code: $rc, а корень / сейчас отвечает другим кодом. Запрос — к корню (путь /), а не к /ping"
            else ok "navidrome_root_code: $rc"; fi
            if [ -z "$rl" ]; then bad "navidrome_location: пусто — ждём значение из строки Location в ответе на запрос к /"
            elif [ "$rl" == "$live_loc" ]; then ok "navidrome_location: $rl"
            else bad "navidrome_location: «$rl» не совпадает со строкой Location в ответе. Нужно только значение, без слова Location:"; fi
        else
            note "navidrome_root_code и navidrome_location проверю, когда будет верный navidrome_port"
        fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. check_http.sh — код ответа"
    if need_script; then
        if grep -q '^max_time=5$' check_http.sh; then ok "max_time=5"
        else bad "строка max_time должна быть ровно max_time=5 (5 секунд, без пробелов у =)"; fi
        if grep -q -- '--max-time' check_http.sh; then ok "у curl есть --max-time"
        else bad "у curl нет --max-time — зависшая служба повесит и проверку"; fi
        if start_fake; then
            SCRIPT=./check_http.sh
            try "$FAKE/code/200" "OK: $FAKE/code/200 - HTTP 200" 0 "ответ 200" \
                "200 — нижняя граница «живого»: от 200 до 399 включительно"
            try "$FAKE/code/301" "OK: $FAKE/code/301 - HTTP 301" 0 "ответ 301 (перенаправление)" \
                "перенаправление — тоже «жив», и по нему не идём: без -L, показываем код самой службы"
            try "$FAKE/code/399" "OK: $FAKE/code/399 - HTTP 399" 0 "ответ 399" \
                "граница: 399 — ещё OK, 400 — уже CRITICAL"
            try "$FAKE/code/400" "CRITICAL: $FAKE/code/400 - HTTP 400" 2 "ответ 400" \
                "граница: 400 — уже CRITICAL. Код выхода CRITICAL — 2"
            try "$FAKE/code/404" "CRITICAL: $FAKE/code/404 - HTTP 404" 2 "ответ 404" "код выхода CRITICAL — 2"
            try "$FAKE/code/500" "CRITICAL: $FAKE/code/500 - HTTP 500" 2 "ответ 500" "код выхода CRITICAL — 2"
        fi
        find_service_ports
        if [ -n "$NAV_PORT" ]; then
            u="http://localhost:$NAV_PORT/ping"
            try "$u" "OK: $u - HTTP 200" 0 "настоящий Navidrome"
        else note "настоящий Navidrome проверю, когда в answers.txt будет верный navidrome_port (шаг 1)"; fi
        if [ -n "$GUI_PORT" ]; then
            u="http://localhost:$GUI_PORT/rest/noauth/health"
            try "$u" "OK: $u - HTTP 200" 0 "настоящий Syncthing"
        else note "настоящий Syncthing проверю, когда в answers.txt будет верный syncthing_gui_port (шаг 1)"; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Нет ответа и неверный запуск"
    if need_script; then
        usage="Usage: ./check_http.sh <url>"
        SCRIPT=./check_http.sh
        run_check
        if [ "$CODE" -eq 3 ] && [ -z "$OUT" ] && [ "$ERR" == "$usage" ]; then ok "без аргументов: «$usage» в stderr, код 3"
        else bad "без аргументов ждём «$usage» в stderr, пустой stdout и код 3; сейчас: stdout «$OUT», stderr «$ERR», код $CODE"; fi
        run_check "http://127.0.0.1:1/" "второй"
        if [ "$CODE" -eq 3 ] && [ -z "$OUT" ] && [ "$ERR" == "$usage" ]; then ok "два аргумента: «$usage» в stderr, код 3"
        else bad "с двумя аргументами ждём «$usage» в stderr, пустой stdout и код 3; сейчас: stdout «$OUT», stderr «$ERR», код $CODE"; fi

        q=$(free_port)
        u="http://127.0.0.1:$q/"
        try "$u" "CRITICAL: $u - no response (curl exit code 7)" 2 "порт никто не слушает"

        u="http://no-such-host.invalid/"
        run_check "$u"
        if [[ "$OUT" =~ ^"CRITICAL: $u - no response (curl exit code "[1-9][0-9]*")"$ ]] && [ "$CODE" -eq 2 ] && [ -z "$ERR" ]; then
            ok "нет такого сервера: «$OUT», код 2"
        else bad "нет такого сервера: ждём «CRITICAL: $u - no response (curl exit code 6)» и код 2; сейчас: «$OUT», код $CODE${ERR:+, в stderr: «$ERR»}"; fi

        if start_fake; then
            # копия скрипта с max_time=2 — чтобы не ждать 5 секунд и проверить, что число берётся из переменной
            sed 's/^max_time=.*/max_time=2/' check_http.sh > "$TMP/check_http_fast.sh"
            chmod +x "$TMP/check_http_fast.sh"
            SCRIPT="$TMP/check_http_fast.sh"
            u="$FAKE/slow"
            try "$u" "CRITICAL: $u - no response (curl exit code 28)" 2 "служба зависла (ответ через 8 с)" \
                "у curl должно быть --max-time \"\$max_time\""
            if [ "$MS" -le 4500 ]; then ok "сдался через $((MS / 1000)) с — время берётся из max_time"
            else bad "с max_time=2 скрипт шёл $((MS / 1000)) с — у curl --max-time не из переменной \$max_time?"; fi
            SCRIPT=./check_http.sh
        fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. Git и README"
    for f in answers.txt check_http.sh; do
        if git ls-files --error-unmatch "$f" > /dev/null 2>&1; then ok "$f добавлен в Git"
        else bad "$f не добавлен в Git (git add)"; fi
    done
    if grep -q '`day25/`' ../../README.md 2>/dev/null; then ok "в README есть строка для day25/"
    else bad "в README (корень репозитория) нет строки для \`day25/\` в таблице Structure"; fi
fi

echo
echo "Итог: ✅ $PASS, ❌ $FAIL"
if [ "$FAIL" -eq 0 ]; then
    if [ "$STEP" == "all" ]; then echo "Все проверки прошли ✅"; else echo "Шаг $STEP пройден ✅"; fi
    exit 0
fi
exit 1
