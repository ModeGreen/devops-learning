#!/bin/bash
# Проверка Задачи 44. Запуск НА СЕРВЕРЕ, из папки задачи:
#   bash check_task44.sh      — всё
#   bash check_task44.sh 2    — только шаг 2 (и так же 1…4)
# Шаг 1: ответы из answers.txt сравниваются с тем, что сервер показывает прямо сейчас
#        (/etc/resolv.conf, resolvectl, getent, dig — только чтение, на сервере ничего не меняется).
#        answers.txt живёт только на сервере: проверка следит, чтобы он, адреса и имена
#        сервера не попали в Git.
# Шаги 2–3: dns_check.sh запускается двумя способами:
#   - с «учебным DNS»: на время запуска проверка подкладывает свою заглушку dig
#     (во временной папке, первой в PATH). Она никуда не ходит, а отвечает так, как нужно
#     проверке: резолвер молчит, имени у резолвера ещё нет, в кэше резолвера старый адрес;
#   - по-настоящему: настоящий dig и публичные резолверы.
#   Твои файлы проверка не меняет.

cd "$(dirname "$0")" || exit 1
STEP="${1:-all}"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
note() { echo "  ℹ️  $1"; }
run_step() { [ "$STEP" == "all" ] || [ "$STEP" == "$1" ]; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT


# --- answers.txt ---
# answer ключ → значение строки «ключ: значение» (пробелы по краям убраны)
answer() {
    [ -f answers.txt ] || return 0
    grep -m 1 "^$1:" answers.txt | cut -d: -f2- | tr -d ' \r'
}
is_ipv4() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
no_dot()  { echo "${1%.}"; }

need_answers() {
    if [ ! -f answers.txt ]; then bad "нет файла answers.txt в папке задачи"; return 1; fi
    if grep -q $'\r' answers.txt; then note "в answers.txt Windows-переводы строк (CRLF) — проверка их пропускает, но лучше LF"; fi
    return 0
}

# --- что сервер показывает прямо сейчас ---
LIVE_NS=$(grep -m 1 '^nameserver' /etc/resolv.conf 2> /dev/null | awk '{print $2}')
LIVE_ROUTE=$(ip route get 1.1.1.1 2> /dev/null | head -n 1)
LIVE_DEV=$(echo "$LIVE_ROUTE" | tr ' ' '\n' | grep -x -A 1 -- dev | sed -n 2p)
LIVE_TS=$(ip -4 -br addr show tailscale0 2> /dev/null | awk '{print $3}' | cut -d/ -f1)
HAVE_TS_IF=0
if ip link show tailscale0 > /dev/null 2>&1; then HAVE_TS_IF=1; fi
HAVE_RESOLVECTL=0
if command -v resolvectl > /dev/null 2>&1 && resolvectl dns > /dev/null 2>&1; then
    HAVE_RESOLVECTL=1
    DNS_ALL=$(resolvectl dns 2> /dev/null)
    DNS_MAIN=""
    if [ -n "$LIVE_DEV" ]; then DNS_MAIN=$(resolvectl dns "$LIVE_DEV" 2> /dev/null); fi
    DNS_TS=""
    if [ "$HAVE_TS_IF" -eq 1 ]; then DNS_TS=$(resolvectl dns tailscale0 2> /dev/null); fi
fi
# server_tokens вывод_resolvectl_dns → адреса серверов, по строке
# («Link 3 (wlp1s0): 192.168.1.1 fe80::1%3» → 192.168.1.1, fe80::1)
server_tokens() {
    echo "$1" | sed -E 's/^[[:space:]]*(Global|Link [0-9]+ \([^)]*\)):[[:space:]]*//' \
        | tr -s ' \t' '\n' | sed 's/[#%].*$//' | grep -v '^$'
}
has_server() { server_tokens "$1" | grep -qxF -- "$2"; }
first_server() { server_tokens "$1" | head -n 1; }

# публичные и служебные адреса — их можно писать где угодно
PUBLIC_OK="1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 9.9.9.9 149.112.112.112 100.100.100.100 127.0.0.53 127.0.0.1"
is_public_ok() { local p; for p in $PUBLIC_OK; do [ "$1" == "$p" ] && return 0; done; return 1; }


# --- Git: answers.txt, адреса и имена сервера не должны попасть в репозиторий ---
in_git() { git ls-files --error-unmatch "$1" > /dev/null 2>&1; }
check_answers_ignored() {
    if in_git answers.txt; then
        bad "answers.txt добавлен в Git, а он должен остаться только на сервере — напиши мне, уберём"
    elif [ -f answers.txt ] && git check-ignore -q answers.txt; then
        ok "answers.txt в Git не попадёт — его игнорирует .gitignore"
    elif [ -f answers.txt ]; then
        bad "answers.txt не игнорируется: нужен .gitignore со строкой answers.txt в папке задачи (подготовка), на сервере — git pull"
    fi
}
# что искать: DNS-сервер сети, адрес Tailscale, имя сервера в Tailscale и домен tailnet
private_values() {
    local a name
    {
        for a in "$LIVE_TS" "$(answer dns_server)" "$(first_server "$DNS_MAIN")"; do
            if is_ipv4 "$a" && ! is_public_ok "$a"; then echo "$a"; fi
        done
        name=$(no_dot "$(answer ts_name)")
        if [[ "$name" == *.ts.net ]]; then
            echo "$name"
            echo "${name#*.}"
        fi
    } | sort -u
}
check_leaks() {
    local v values leaks=0 files
    values=$(private_values)
    if [ -z "$values" ]; then
        note "утечку адресов и имён проверю, когда в answers.txt будут dns_server и ts_name"
        return
    fi
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        files=$(git grep -l -F -w -e "$v" -- . ../../README.md ':(exclude)check_task44.sh' ':(exclude)answers.txt' 2> /dev/null | tr '\n' ' ')
        if [ -n "$files" ]; then
            bad "в файлах репозитория есть адрес или имя твоей сети ($files) — убери. Если уже запушено — напиши мне"
            leaks=1
        fi
        if git log --format='%B' main..HEAD 2> /dev/null | grep -q -F -w -e "$v"; then
            bad "в сообщении коммита ветки task44 есть адрес или имя твоей сети — напиши мне, поправим историю"
            leaks=1
        fi
    done <<< "$values"
    if [ "$leaks" -eq 0 ]; then ok "адресов и имён твоей сети нет ни в файлах репозитория, ни в сообщениях коммитов"; fi
}


# --- «учебный DNS»: заглушка dig ---
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/dig" <<'SH'
#!/bin/bash
# Заглушка dig для проверки Задачи 44: никуда не ходит, отвечает из своей таблицы.
# FAKE_DOWN — резолверы, которые молчат (как настоящий dig: текст ошибки в stdout, код 9);
# FAKE_OLD  — резолверы, у которых в кэше старый адрес 198.51.100.7;
# FAKE_NX   — резолверы, у которых имени ещё нет (пустой ответ, код 0 — как NXDOMAIN).
args="$*"
echo "${args//$'\n'/\\n}" >> "$FAKE_LOG"
server=""; have_server=0; short=0; name=""; type=A
for a in "$@"; do
    case "$a" in
        @*) server="${a#@}"; have_server=1 ;;
        +short) short=1 ;;
        +time=)  echo "Invalid option: +time" >&2; exit 1 ;;
        +tries=) echo "Invalid option: +tries" >&2; exit 1 ;;
        +time=*)
            t="${a#+time=}"
            if ! [[ "$t" =~ ^[0-9]+$ ]]; then echo "invalid timeout '$t': not a valid number" >&2; echo "dig: Couldn't parse timeout" >&2; exit 10; fi ;;
        +tries=*)
            t="${a#+tries=}"
            if ! [[ "$t" =~ ^[0-9]+$ ]]; then echo "invalid tries '$t': not a valid number" >&2; echo "dig: Couldn't parse tries" >&2; exit 10; fi ;;
        +*) ;;
        A|AAAA|CNAME|MX|TXT|NS|SOA|a|aaaa|cname) type="${a^^}" ;;
        -*) ;;
        *) if [ -z "$name" ]; then name="$a"; fi ;;
    esac
done
if [ "$have_server" -eq 1 ] && { [ -z "$server" ] || [[ "$server" == *" "* || "$server" == *$'\n'* ]]; }; then
    echo "dig: couldn't get address for '$server': not found" >&2
    exit 1
fi
if [ "$have_server" -eq 0 ]; then server=127.0.0.53; fi
if [ -z "$name" ]; then name="."; type=NS; fi
if [[ "$name" == *" "* || "$name" == *$'\n'* ]]; then
    echo "dig: '$name' is not a legal name (bad label type)" >&2
    exit 10
fi
in_list() { local x; for x in $2; do [ "$x" == "$1" ] && return 0; done; return 1; }

if in_list "$server" "$FAKE_DOWN"; then
    echo ";; communications error to $server#53: timed out"
    echo ";; no servers could be reached"
    exit 9
fi

answer=""
if [ "$type" == "A" ] && ! in_list "$server" "$FAKE_NX"; then
    case "${name%.}" in
        shop.example.com)     answer="203.0.113.20" ;;
        www.shop.example.com) answer=$'shop.example.com.\n203.0.113.20' ;;
        cdn.shop.example.com) answer=$'203.0.113.21\n203.0.113.22' ;;
        one.one.one.one)      answer=$'1.1.1.1\n1.0.0.1' ;;
    esac
    if [ -n "$answer" ] && in_list "$server" "$FAKE_OLD"; then
        if [ "${name%.}" == "www.shop.example.com" ]; then answer=$'shop.example.com.\n198.51.100.7'
        else answer="198.51.100.7"; fi
    fi
fi

if [ "$short" -eq 1 ]; then
    if [ -n "$answer" ]; then echo "$answer"; fi
    exit 0
fi
# без +short — полный ответ, как у настоящего dig
status=NOERROR
count=0
if [ -n "$answer" ]; then count=$(echo "$answer" | wc -l); else status=NXDOMAIN; fi
echo
echo "; <<>> DiG 9.20 (учебная заглушка) <<>> $*"
echo ";; global options: +cmd"
echo ";; Got answer:"
echo ";; ->>HEADER<<- opcode: QUERY, status: $status, id: 4242"
echo ";; flags: qr rd ra; QUERY: 1, ANSWER: $count, AUTHORITY: 0, ADDITIONAL: 1"
echo
echo ";; QUESTION SECTION:"
echo ";${name%.}.			IN	$type"
if [ -n "$answer" ]; then
    echo
    echo ";; ANSWER SECTION:"
    owner="${name%.}."
    while IFS= read -r line; do
        if [[ "$line" == *. ]]; then
            echo "$owner	300	IN	CNAME	$line"
            owner="$line"
        else
            echo "$owner	300	IN	A	$line"
        fi
    done <<< "$answer"
fi
echo
echo ";; Query time: 1 msec"
echo ";; SERVER: $server#53($server) (UDP)"
echo
exit 0
SH
chmod +x "$FAKEBIN/dig"


# --- dns_check.sh ---
SCRIPT=./dns_check.sh
USAGE="Usage: ./dns_check.sh <name> <expected_ip>"
FORM=""   # 2 — один резолвер (resolver=), 3 — несколько (resolvers=)

# need_script N — файл есть и запускается; переменные на месте
need_script() {
    local f=dns_check.sh
    if [ ! -f "$f" ]; then bad "нет файла $f в папке задачи"; return 1; fi
    if [ ! -x "$f" ]; then bad "$f не запускается как программа — нет права x (chmod +x в WSL, коммит, push, pull)"; return 1; fi
    if grep -q $'\r' "$f"; then bad "$f: Windows-переводы строк (^M) — в VS Code внизу справа CRLF → LF"; return 1; fi
    if [ "$(head -n 1 "$f")" != "#!/bin/bash" ]; then bad "$f: первая строка не #!/bin/bash"; return 1; fi
    if [ "$(grep -c '^max_wait=' "$f")" -ne 1 ]; then bad "$f: нужна одна строка, которая начинается с max_wait= (сколько секунд ждать ответа)"; return 1; fi
    if grep -Eq '/(usr/)?s?bin/dig([^a-z_]|$)' "$f"; then
        bad "$f: dig вызывай по имени, без пути (/usr/bin/…): иначе проверка не сможет подложить свою заглушку"
        return 1
    fi
    local n2 n3
    n2=$(grep -c '^resolver=' "$f")
    n3=$(grep -c '^resolvers=' "$f")
    if [ "$n3" -eq 1 ] && [ "$n2" -eq 0 ]; then FORM=3
    elif [ "$n2" -eq 1 ] && [ "$n3" -eq 0 ]; then FORM=2
    elif [ "$n2" -ge 1 ] && [ "$n3" -ge 1 ]; then
        bad "$f: есть и resolver=, и resolvers= — в шаге 3 строка resolver= заменяется на resolvers=, старую убери"
        return 1
    else
        bad "$f: нужна одна строка resolver=1.1.1.1 (шаг 2) или resolvers=\"…\" (шаг 3)"
        return 1
    fi
    if [ "$1" == "3" ] && [ "$FORM" != "3" ]; then
        bad "$f: в шаге 3 строка resolver=1.1.1.1 заменяется на resolvers=\"1.1.1.1 8.8.8.8 9.9.9.9\""
        return 1
    fi
    return 0
}

# copy_with "команда sed" → путь к копии скрипта с другими значениями переменных
COPY_N=0
copy_with() {
    COPY_N=$((COPY_N + 1))
    sed "$1" dns_check.sh > "$TMP/copy$COPY_N.sh"
    chmod +x "$TMP/copy$COPY_N.sh"
    echo "$TMP/copy$COPY_N.sh"
}
# одна строка с резолверами: для скрипта шага 2 — resolver=X, для шага 3 — resolvers="X Y"
set_resolvers() {
    if [ "$FORM" == "3" ]; then echo "s/^resolvers=.*/resolvers=\"$1\"/"
    else echo "s/^resolver=.*/resolver=$1/"; fi
}

# run_fake [ПЕРЕМЕННАЯ=значение для заглушки …] -- аргументы скрипта
# → OUT, ERR, CODE, CALLS (по строке на вызов dig)
RUN_MODE=fake
run_fake() {
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    RUN_MODE=fake
    : > "$TMP/dig.log"
    env PATH="$FAKEBIN:$PATH" FAKE_LOG="$TMP/dig.log" "${envs[@]}" \
        timeout 20 "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err" < /dev/null
    CODE=$?
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
    CALLS=$(cat "$TMP/dig.log")
}
# run_real аргументы → то же, но по-настоящему: настоящий dig и публичные резолверы
run_real() {
    RUN_MODE=real
    timeout 60 "$SCRIPT" "$@" > "$TMP/out" 2> "$TMP/err" < /dev/null
    CODE=$?
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
    CALLS=""
}
calls_count() { if [ -z "$CALLS" ]; then echo 0; else echo "$CALLS" | wc -l; fi; }
line_n() { echo "$OUT" | sed -n "${1}p"; }
# show текст — в одну строку (⏎ вместо перевода строки), не длиннее 300 символов
show() {
    local s="${1//$'\n'/ ⏎ }"
    if [ "${#s}" -gt 300 ]; then s="${s:0:300} …"; fi
    echo "$s"
}

# hint текст — подсказка, но одна и та же только один раз
SHOWN=""
hint() {
    case "$SHOWN" in *"|$1|"*) return ;; esac
    SHOWN="$SHOWN|$1|"
    note "$1"
}
# общие подсказки по неверному выводу
explain() {
    if [ "$CODE" -eq 124 ]; then hint "скрипт не закончился вовремя — что-то ждёт ввода или висит"; fi
    if [[ "$OUT" == *"communications error"* || "$OUT" == *"no servers could be reached"* ]]; then
        hint "в выводе — текст ошибки dig: резолвер молчал, а скрипт принял этот текст за ответ. Сначала проверяй код выхода dig (не 0 → does not reply), потом содержимое ответа"
    fi
    if [[ "$OUT" == *"ANSWER SECTION"* || "$OUT" == *"HEADER"* || "$OUT" == *"QUESTION SECTION"* ]]; then
        hint "в выводе — полный ответ dig с шапкой. У dig в скрипте нет +short?"
    fi
    if [[ "$ERR" == *"couldn't get address for"* ]]; then
        hint "dig не понял адрес резолвера: «$(echo "$ERR" | head -n 1)». Если в нём несколько адресов через пробел — список в for стоит в кавычках, и цикл прошёл один раз со всей строкой. Здесь переменная — без кавычек"
    fi
    if [[ "$ERR" == *"Invalid option: +time"* || "$ERR" == *"Couldn't parse timeout"* ]]; then
        hint "dig не понял +time: «$(echo "$ERR" | head -n 1)». После +time= должно стоять число из \$max_wait"
    fi
    if [ "$RUN_MODE" == "fake" ] && [ "$CODE" -ne 124 ] && [ "$(calls_count)" -eq 0 ] && [ -n "$OUT" ]; then
        hint "заглушка dig ни разу не вызвалась — dig в скрипте вызывается по имени? Проверка подставляет свою команду dig"
    fi
    if echo "$OUT" | grep -qE '^[0-9]|^[a-z0-9.-]+\.$|^[a-z0-9.-]+\., expected'; then
        hint "адреса в сообщении разорваны на строки — склей их в одну через paste -sd ' '"
    fi
}

# expect что_проверяем ждём_вывод ждём_код [подсказка] (после run_fake/run_real)
expect() {
    if [ "$OUT" == "$2" ] && [ "$CODE" -eq "$3" ] && [ -z "$ERR" ]; then
        ok "$1: код $CODE"
        return 0
    fi
    bad "$1: ждём «${2//$'\n'/ ⏎ }» и код $3; сейчас: «$(show "$OUT")», код $CODE${ERR:+, в stderr: «$(show "$ERR")»}"
    explain
    if [ "$OUT" == "$2" ] && [ -n "$ERR" ]; then hint "вывод и код верные, но в stderr что-то есть — там должно быть пусто"
    elif [ "$OUT" == "$2" ]; then hint "вывод верный, а код выхода нет: все OK — 0, есть CRITICAL — 2"
    else
        local i=1 e a total
        total=$(echo "$2" | wc -l)
        while [ "$i" -le "$total" ]; do
            e=$(echo "$2" | sed -n "${i}p")
            a=$(line_n "$i")
            if [ "$e" != "$a" ]; then break; fi
            i=$((i + 1))
        done
        if [ "$i" -gt "$total" ]; then hint "лишние строки после «$(echo "$2" | tail -n 1)»"
        elif [ -n "$4" ] && [ -n "$a" ] && [[ "$a" == "${e%% *}"* ]]; then hint "$4"
        elif [ -z "$a" ] && [[ "$e" == Checked* ]] && [[ "$(echo "$OUT" | tail -n 1)" == CRITICAL* ]]; then
            hint "итоговой строки нет, а последняя — CRITICAL: скрипт вышел внутри цикла? exit в цикле не нужен — проблемы считаются в переменной, выход — после итога"
        elif [ -z "$a" ]; then hint "строки $i нет: ждём «$e»"
        else hint "строка $i не совпала: ждём «$(show "$e")», сейчас «$(show "$a")» — сравни буква в букву"; fi
    fi
    return 1
}
# expect_first что ждём_первую_строку ждём_код [подсказка] — для шага 2:
# у скрипта шага 2 строка должна быть одна, у скрипта шага 3 сравниваем только первую
expect_first() {
    if [ "$FORM" == "2" ]; then expect "$@"; return; fi
    if [ "$(line_n 1)" == "$2" ] && [ "$CODE" -eq "$3" ] && [ -z "$ERR" ]; then ok "$1: код $CODE"; return 0; fi
    bad "$1: ждём первую строку «$2» и код $3; сейчас: «$(show "$OUT")», код $CODE${ERR:+, в stderr: «$(show "$ERR")»}"
    explain
    return 1
}

# флаги вызовов dig: +short, +time=<max_wait>, +tries=1, @резолвер
check_dig_flags() {
    local wait=$1 line miss_short=0 miss_time=0 miss_tries=0 miss_at=0
    if [ -z "$CALLS" ]; then bad "dig ни разу не вызвался"; return; fi
    while IFS= read -r line; do
        [[ " $line " == *" +short "* ]] || miss_short=1
        [[ " $line " == *" +time=$wait "* ]] || miss_time=1
        [[ " $line " == *" +tries=1 "* ]] || miss_tries=1
        [[ " $line " == *" @"* ]] || miss_at=1
    done <<< "$CALLS"
    if [ "$miss_short" -eq 0 ]; then ok "dig с +short — только значения"
    else bad "не у каждого вызова dig есть +short. Вызовы: «${CALLS//$'\n'/ | }»"; fi
    if [ "$miss_time" -eq 0 ] && [ "$miss_tries" -eq 0 ]; then ok "dig ждёт не дольше max_wait ($wait с) и спрашивает один раз (+time=$wait +tries=1)"
    else bad "у dig должно быть +time=$wait (из \$max_wait) и +tries=1. Вызовы: «${CALLS//$'\n'/ | }»"; fi
    if [ "$miss_at" -eq 1 ]; then bad "dig вызван без @резолвера — тогда он спрашивает DNS самого сервера, а не 1.1.1.1. Вызовы: «${CALLS//$'\n'/ | }»"; fi
}


# ---------------------------------------------------------------
if run_step 1; then
    echo "Шаг 1. Как сервер ищет имена"
    if need_answers; then
        check_answers_ignored

        v=$(answer nameserver)
        if [ -z "$LIVE_NS" ]; then note "в /etc/resolv.conf нет строки nameserver — nameserver не проверяю, напиши мне"
        elif [ -z "$v" ]; then bad "nameserver: пусто — ждём адрес из строки nameserver в /etc/resolv.conf"
        elif [ "$v" == "$LIVE_NS" ]; then
            ok "nameserver: $v"
            if [ "$LIVE_NS" != "127.0.0.53" ]; then note "у тебя в /etc/resolv.conf не 127.0.0.53 — значит, не systemd-resolved. Напиши мне, разберём"; fi
        else bad "nameserver: «$v», а в /etc/resolv.conf первая строка nameserver — другая"; fi

        if [ "$HAVE_RESOLVECTL" -eq 0 ]; then
            note "resolvectl на сервере не работает — dns_server и ts_dns не проверяю, напиши мне"
        else
            v=$(answer dns_server)
            if [ -z "$v" ]; then bad "dns_server: пусто — ждём адрес из resolvectl dns у интерфейса $LIVE_DEV"
            elif [ "$v" == "127.0.0.53" ]; then bad "dns_server: 127.0.0.53 — это сам systemd-resolved. Нужен сервер, которому он пересылает вопросы: resolvectl dns, строка интерфейса $LIVE_DEV"
            elif [ "$v" == "100.100.100.100" ]; then bad "dns_server: 100.100.100.100 — это DNS Tailscale (интерфейс tailscale0), он пойдёт в ts_dns. Здесь нужен DNS главного интерфейса $LIVE_DEV"
            elif has_server "$DNS_MAIN" "$v"; then ok "dns_server: DNS-сервер интерфейса $LIVE_DEV верный"
            elif [ -z "$(server_tokens "$DNS_MAIN")" ] && has_server "$DNS_ALL" "$v"; then
                ok "dns_server: у $LIVE_DEV своих DNS-серверов нет, а этот — общий (Global). Засчитано"
            else bad "dns_server: «$v» не DNS-сервер интерфейса $LIVE_DEV. Смотри resolvectl dns: строка Link … ($LIVE_DEV)"; fi

            v=$(answer ts_dns)
            if [ "$HAVE_TS_IF" -eq 0 ]; then note "интерфейса tailscale0 на сервере сейчас нет — ts_dns не проверяю"
            elif [ -z "$v" ]; then bad "ts_dns: пусто — ждём DNS-сервер из строки tailscale0 в resolvectl dns, или none"
            elif [ "$v" == "none" ]; then
                if [ -z "$(server_tokens "$DNS_TS")" ]; then ok "ts_dns: none — у tailscale0 DNS-серверов нет (MagicDNS на сервере не включён)"
                else bad "ts_dns: none, а у tailscale0 DNS-сервер есть — посмотри строку tailscale0 в resolvectl dns"; fi
            elif has_server "$DNS_TS" "$v"; then ok "ts_dns: $v"
            elif has_server "$DNS_MAIN" "$v"; then bad "ts_dns: «$v» — это DNS главного интерфейса $LIVE_DEV, а нужен DNS у tailscale0"
            else bad "ts_dns: «$v» не DNS-сервер tailscale0 — смотри строку tailscale0 в resolvectl dns"; fi
        fi

        v=$(no_dot "$(answer ts_name)")
        live_ts_dns=$(server_tokens "$DNS_TS")
        if [ "$HAVE_TS_IF" -eq 0 ]; then note "интерфейса tailscale0 на сервере сейчас нет — ts_name не проверяю"
        elif [ -z "$v" ]; then bad "ts_name: пусто — ждём полное имя сервера в Tailscale (…ts.net), или none"
        elif [ "$v" == "none" ]; then
            if [ "$HAVE_RESOLVECTL" -eq 1 ] && [ -z "$live_ts_dns" ]; then ok "ts_name: none — MagicDNS на сервере не работает, засчитано"
            else bad "ts_name: none, а MagicDNS на сервере работает (у tailscale0 есть DNS-сервер) — имя есть"; fi
        elif [[ "$v" != *.* ]]; then bad "ts_name: «$v» — это короткое имя машины. Нужно полное: имя машины + точка + домен tailnet (…ts.net)"
        elif [[ "$v" != *.ts.net ]]; then bad "ts_name: «$v» — полное имя в Tailscale кончается на .ts.net"
        elif [ -z "$LIVE_TS" ]; then note "у tailscale0 сейчас нет IPv4-адреса — ts_name проверяю только по виду: ок"; PASS=$((PASS + 1))
        else
            got=$(getent ahostsv4 "$v" 2> /dev/null | awk 'NR == 1 {print $1}')
            if [ "$got" == "$LIVE_TS" ]; then ok "ts_name: имя находится и ведёт на адрес tailscale0"
            elif [ -z "$got" ]; then bad "ts_name: «$v» не находится — проверь руками: dig +short $v. Сверь имя машины в tailscale status и домен в resolvectl domain tailscale0"
            else bad "ts_name: «$v» ведёт на $got, а у tailscale0 другой адрес — это имя другого устройства?"; fi
        fi

        v=$(no_dot "$(answer cname)")
        live=""
        if command -v dig > /dev/null 2>&1; then
            live=$(no_dot "$(dig +short +time=3 +tries=2 www.github.com CNAME 2> /dev/null | head -n 1)")
        fi
        if [ -z "$v" ]; then bad "cname: пусто — ждём имя из строки CNAME в ответе dig www.github.com"
        elif is_ipv4 "$v"; then bad "cname: «$v» — это адрес (строка A). Нужно имя из строки CNAME"
        elif [ "$v" == "www.github.com" ]; then bad "cname: www.github.com — это само имя-псевдоним (первая колонка). Нужно то, на что он указывает (последняя колонка строки CNAME)"
        elif [ -z "$live" ]; then
            if command -v dig > /dev/null 2>&1; then note "dig не получил CNAME у www.github.com — сравниваю с тем, что было на 2026-11-25"; fi
            if [ "$v" == "github.com" ]; then ok "cname: github.com"; else bad "cname: «$v» — сверь со строкой CNAME в dig www.github.com"; fi
        elif [ "$v" == "$live" ]; then ok "cname: $v"
        else bad "cname: «$v», а dig сейчас показывает CNAME на $live"; fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. dns_check.sh — один резолвер"
    if need_script 2; then
        if grep -Eq "^max_wait=[\"']?2[\"']?$" dns_check.sh; then ok "max_wait=2"
        else bad "строка max_wait должна быть ровно max_wait=2 (2 секунды, без пробелов у =)"; fi
        if [ "$FORM" == "2" ]; then
            if grep -Eq "^resolver=[\"']?1\.1\.1\.1[\"']?$" dns_check.sh; then ok "resolver=1.1.1.1"
            else bad "строка должна быть ровно resolver=1.1.1.1"; fi
        else
            note "скрипт уже в виде шага 3 — шаг 2 проверяю на копии с одним резолвером 1.1.1.1 (только первую строку вывода)"
        fi

        # Неверный запуск — до dig
        for args in "" "shop.example.com" "shop.example.com 203.0.113.20 extra"; do
            SCRIPT=./dns_check.sh
            # shellcheck disable=SC2086
            run_fake -- $args
            n=$(echo "$args" | wc -w)
            if [ -z "$OUT" ] && [ "$ERR" == "$USAGE" ] && [ "$CODE" -eq 3 ]; then ok "аргументов $n — Usage в stderr, код 3"
            else
                bad "аргументов $n: ждём в stderr «$USAGE», в stdout пусто, код 3; сейчас stdout «$(show "$OUT")», stderr «$(show "$ERR")», код $CODE"
                if [ "$OUT" == "$USAGE" ]; then hint "Usage ушёл в stdout — нужен >&2 (урок 11)"; fi
                if [ "$CODE" -eq 3 ] && [[ "$ERR" == Usage:* ]] && [ "$ERR" != "$USAGE" ]; then hint "текст Usage — буква в букву, как в условии: <name> и <expected_ip> — часть текста"; fi
            fi
            if [ "$(calls_count)" -gt 0 ]; then bad "при неверном запуске скрипт всё равно вызвал dig — проверка аргументов должна быть первой"; fi
        done

        SCRIPT=$(copy_with "$(set_resolvers 1.1.1.1)")
        run_fake -- shop.example.com 203.0.113.20
        expect_first "адрес верный" "OK: 1.1.1.1 resolves shop.example.com to 203.0.113.20" 0
        check_dig_flags 2
        if [[ "$(echo "$CALLS" | head -n 1)" == *"@1.1.1.1"* ]]; then ok "dig спрашивает резолвер 1.1.1.1"; fi

        run_fake -- www.shop.example.com 203.0.113.20
        expect_first "имя через CNAME (первая строка ответа — имя, вторая — адрес)" "OK: 1.1.1.1 resolves www.shop.example.com to 203.0.113.20" 0
        if [[ "$(line_n 1)" == "CRITICAL: 1.1.1.1 resolves www.shop.example.com to shop.example.com. 203.0.113.20"* ]]; then
            hint "у имени с CNAME ответ — две строки, адрес во второй. Ищи нужную строку среди всех: echo \"\$answer\" | grep -qxF …, а не сравнивай весь ответ"
        fi

        run_fake -- cdn.shop.example.com 203.0.113.22
        expect_first "у имени два адреса, нужный — второй" "OK: 1.1.1.1 resolves cdn.shop.example.com to 203.0.113.22" 0

        run_fake -- shop.example.com 203.0.113.2
        expect_first "ждём 203.0.113.2, а у имени 203.0.113.20" "CRITICAL: 1.1.1.1 resolves shop.example.com to 203.0.113.20, expected 203.0.113.2" 2
        if [[ "$(line_n 1)" == OK:* ]]; then hint "203.0.113.2 — только начало строки 203.0.113.20, а скрипт посчитал это совпадением. Строка должна совпасть целиком: grep -x"; fi

        run_fake FAKE_OLD=1.1.1.1 -- shop.example.com 203.0.113.20
        expect_first "у резолвера старый адрес" "CRITICAL: 1.1.1.1 resolves shop.example.com to 198.51.100.7, expected 203.0.113.20" 2

        run_fake -- cdn.shop.example.com 203.0.113.99
        expect_first "два адреса, нужного среди них нет" "CRITICAL: 1.1.1.1 resolves cdn.shop.example.com to 203.0.113.21 203.0.113.22, expected 203.0.113.99" 2

        run_fake FAKE_NX=1.1.1.1 -- shop.example.com 203.0.113.20
        expect_first "имени у резолвера нет" "CRITICAL: 1.1.1.1 has no address for shop.example.com" 2

        run_fake FAKE_DOWN=1.1.1.1 -- shop.example.com 203.0.113.20
        expect_first "резолвер молчит" "CRITICAL: 1.1.1.1 does not reply" 2

        # max_wait и резолвер — из переменных
        SCRIPT=$(copy_with "s/^max_wait=.*/max_wait=1/; $(set_resolvers 1.1.1.1)")
        run_fake -- shop.example.com 203.0.113.20
        if [[ " $(echo "$CALLS" | head -n 1) " == *" +time=1 "* ]]; then ok "с max_wait=1 dig ждёт 1 секунду — число берётся из переменной"
        else bad "с max_wait=1 dig вызван так: «$(echo "$CALLS" | head -n 1)» — время ожидания не из \$max_wait?"; fi
        SCRIPT=$(copy_with "$(set_resolvers 9.9.9.9)")
        run_fake -- shop.example.com 203.0.113.20
        if [[ "$(echo "$CALLS" | head -n 1)" == *"@9.9.9.9"* ]] && [ "$(line_n 1)" == "OK: 9.9.9.9 resolves shop.example.com to 203.0.113.20" ]; then
            ok "с резолвером 9.9.9.9 спрашивается он — адрес берётся из переменной"
        else bad "с резолвером 9.9.9.9 ждём вызов dig @9.9.9.9 и строку «OK: 9.9.9.9 resolves shop.example.com to 203.0.113.20»; сейчас: вызов «$(echo "$CALLS" | head -n 1)», строка «$(line_n 1)»"; fi

        # По-настоящему: один резолвер 1.1.1.1
        SCRIPT=$(copy_with "$(set_resolvers 1.1.1.1)")
        run_real one.one.one.one 1.0.0.1
        expect_first "по-настоящему: one.one.one.one у 1.1.1.1 (нужен второй из двух адресов)" "OK: 1.1.1.1 resolves one.one.one.one to 1.0.0.1" 0
        if [[ "$(line_n 1)" == *"does not reply"* ]]; then hint "сервер не получил ответа от 1.1.1.1 — проверь руками: dig +short @1.1.1.1 one.one.one.one. Не отвечает — напиши мне"; fi
        run_real one.one.one.one 203.0.113.10
        first=$(line_n 1)
        if [[ "$first" == "CRITICAL: 1.1.1.1 resolves one.one.one.one to "*", expected 203.0.113.10" && ( "$first" == *" 1.1.1.1 1.0.0.1,"* || "$first" == *" 1.0.0.1 1.1.1.1,"* ) ]] && [ "$CODE" -eq 2 ]; then
            ok "по-настоящему, чужой адрес: «$first», код 2"
        else
            bad "по-настоящему, one.one.one.one и 203.0.113.10: ждём «CRITICAL: 1.1.1.1 resolves one.one.one.one to 1.1.1.1 1.0.0.1, expected 203.0.113.10» (адреса — в любом порядке) и код 2; сейчас: «$(show "$OUT")», код $CODE${ERR:+, в stderr: «$(show "$ERR")»}"
            explain
        fi
        SCRIPT=./dns_check.sh
    fi
fi

if run_step 3; then
    echo "Шаг 3. Несколько резолверов"
    if need_script 3; then
        if grep -Eq "^resolvers=[\"']1\.1\.1\.1 8\.8\.8\.8 9\.9\.9\.9[\"']$" dns_check.sh; then ok "resolvers=\"1.1.1.1 8.8.8.8 9.9.9.9\""
        else bad "строка должна быть ровно resolvers=\"1.1.1.1 8.8.8.8 9.9.9.9\""; fi

        SCRIPT=./dns_check.sh
        run_fake -- shop.example.com 203.0.113.20
        if [ "$(calls_count)" -eq 1 ] && [[ "$CALLS" == *"@1.1.1.1 8.8.8.8 9.9.9.9"* ]]; then
            hint "dig вызван один раз со всеми адресами сразу: список в for стоит в кавычках. Здесь переменная — без кавычек: так bash делит её по пробелам на слова"
        fi
        expect "все три резолвера видят адрес" "OK: 1.1.1.1 resolves shop.example.com to 203.0.113.20
OK: 8.8.8.8 resolves shop.example.com to 203.0.113.20
OK: 9.9.9.9 resolves shop.example.com to 203.0.113.20
Checked 3 resolvers. Problems: 0" 0 "итог — отдельной строкой после цикла: Checked <сколько резолверов> resolvers. Problems: <сколько CRITICAL>"
        if [ "$(calls_count)" -eq 3 ]; then check_dig_flags 2
        else bad "ждём 3 вызова dig (по одному на резолвер), сейчас — $(calls_count): «${CALLS//$'\n'/ | }»"; fi

        run_fake FAKE_OLD=8.8.8.8 -- shop.example.com 203.0.113.20
        expect "у 8.8.8.8 в кэше старый адрес" "OK: 1.1.1.1 resolves shop.example.com to 203.0.113.20
CRITICAL: 8.8.8.8 resolves shop.example.com to 198.51.100.7, expected 203.0.113.20
OK: 9.9.9.9 resolves shop.example.com to 203.0.113.20
Checked 3 resolvers. Problems: 1" 2 "после CRITICAL цикл идёт дальше: exit внутри цикла не нужен, проблемы считаются в переменной"
        if [ "$(calls_count)" -lt 3 ]; then bad "после первой проблемы скрипт остановился (вызовов dig: $(calls_count)) — внутри цикла exit не нужен: опросить надо все резолверы"; fi

        run_fake FAKE_NX=8.8.8.8 FAKE_DOWN=9.9.9.9 -- www.shop.example.com 203.0.113.20
        expect "у 8.8.8.8 имени ещё нет, 9.9.9.9 молчит" "OK: 1.1.1.1 resolves www.shop.example.com to 203.0.113.20
CRITICAL: 8.8.8.8 has no address for www.shop.example.com
CRITICAL: 9.9.9.9 does not reply
Checked 3 resolvers. Problems: 2" 2

        run_fake FAKE_OLD=9.9.9.9 -- www.shop.example.com 203.0.113.20
        expect "у 9.9.9.9 старый адрес, имя через CNAME" "OK: 1.1.1.1 resolves www.shop.example.com to 203.0.113.20
OK: 8.8.8.8 resolves www.shop.example.com to 203.0.113.20
CRITICAL: 9.9.9.9 resolves www.shop.example.com to shop.example.com. 198.51.100.7, expected 203.0.113.20
Checked 3 resolvers. Problems: 1" 2

        run_fake "FAKE_DOWN=1.1.1.1 8.8.8.8 9.9.9.9" -- shop.example.com 203.0.113.20
        expect "все три молчат" "CRITICAL: 1.1.1.1 does not reply
CRITICAL: 8.8.8.8 does not reply
CRITICAL: 9.9.9.9 does not reply
Checked 3 resolvers. Problems: 3" 2

        run_fake -- shop.example.com
        if [ -z "$OUT" ] && [ "$ERR" == "$USAGE" ] && [ "$CODE" -eq 3 ] && [ "$(calls_count)" -eq 0 ]; then ok "неверный запуск — по-прежнему Usage и код 3"
        else bad "неверный запуск (1 аргумент): ждём Usage в stderr и код 3 до любых dig; сейчас stdout «$(show "$OUT")», stderr «$(show "$ERR")», код $CODE"; fi

        # список резолверов — из переменной
        SCRIPT=$(copy_with 's/^resolvers=.*/resolvers="1.1.1.1 9.9.9.9"/')
        run_fake -- cdn.shop.example.com 203.0.113.21
        expect "с resolvers=\"1.1.1.1 9.9.9.9\" — два резолвера" "OK: 1.1.1.1 resolves cdn.shop.example.com to 203.0.113.21
OK: 9.9.9.9 resolves cdn.shop.example.com to 203.0.113.21
Checked 2 resolvers. Problems: 0" 0 "число в итоге — сколько резолверов опрошено на самом деле, а не 3: считай их в цикле"

        # По-настоящему
        SCRIPT=./dns_check.sh
        run_real one.one.one.one 1.1.1.1
        expect "по-настоящему: one.one.one.one у трёх публичных резолверов" "OK: 1.1.1.1 resolves one.one.one.one to 1.1.1.1
OK: 8.8.8.8 resolves one.one.one.one to 1.1.1.1
OK: 9.9.9.9 resolves one.one.one.one to 1.1.1.1
Checked 3 resolvers. Problems: 0" 0
        if [[ "$OUT" == *"does not reply"* ]]; then hint "какой-то резолвер не ответил серверу. Проверь руками: dig +short @<резолвер> one.one.one.one. Не отвечает — напиши мне"; fi
        if [ "$STEP" != "all" ]; then check_leaks; fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. Git и README"
    for f in .gitignore dns_check.sh; do
        if in_git "$f"; then ok "$f добавлен в Git"
        else bad "$f не добавлен в Git (git add)"; fi
    done
    if [ -f answers.txt ]; then check_answers_ignored
    else bad "нет answers.txt на сервере, в папке задачи (шаг 1)"; fi
    if [ -n "$(git log --oneline main..HEAD -- answers.txt 2> /dev/null)" ]; then
        bad "answers.txt есть в истории ветки task44 (в одном из коммитов) — напиши мне, уберём"
    fi
    check_leaks
    if grep -q '`day28/`' ../../README.md 2> /dev/null; then ok "в README есть строка для day28/"
    else bad "в README (корень репозитория) нет строки для \`day28/\` в таблице Structure"; fi
    if [ -n "$(git status --porcelain -- . ../../README.md 2> /dev/null)" ]; then
        bad "git status: в папке задачи или в README есть незакоммиченные изменения — $(git status --porcelain -- . ../../README.md | tr '\n' ' ')"
    else ok "git status: в папке задачи и README всё закоммичено"; fi
fi

echo
echo "Итог: ✅ $PASS, ❌ $FAIL"
if [ "$FAIL" -eq 0 ]; then
    if [ "$STEP" == "all" ]; then echo "Все проверки прошли ✅"; else echo "Шаг $STEP пройден ✅"; fi
    exit 0
fi
exit 1
