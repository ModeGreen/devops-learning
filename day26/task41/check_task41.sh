#!/bin/bash
# Проверка Задачи 41. Запуск НА СЕРВЕРЕ, из папки задачи:
#   bash check_task41.sh      — всё
#   bash check_task41.sh 2    — только шаг 2 (и так же 1…4)
# Шаг 1: ответы из answers.txt сравниваются с тем, что сервер показывает прямо сейчас
#        (ip route get, ip addr — только чтение, на сервере ничего не меняется).
#        answers.txt живёт только на сервере: проверка следит, чтобы он и адреса сервера
#        не попали в Git.
# Шаги 2–3: net_diag.sh запускается двумя способами:
#   - в «учебной сети»: на время запуска проверка подкладывает свои заглушки ip и ping
#     (во временной папке, первой в PATH). Они ничего не отправляют, а изображают поломки,
#     которые на живом сервере устраивать нельзя: нет маршрута, шлюз молчит, нет интернета,
#     не работает DNS;
#   - по-настоящему, на сети сервера: там всё должно быть OK.
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
is_int()  { [[ "$1" =~ ^[0-9]+$ ]]; }
is_ipv4() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }

need_answers() {
    if [ ! -f answers.txt ]; then bad "нет файла answers.txt в папке задачи"; return 1; fi
    if grep -q $'\r' answers.txt; then note "в answers.txt Windows-переводы строк (CRLF) — проверка их пропускает, но лучше LF"; fi
    return 0
}

# --- что сервер показывает прямо сейчас ---
# ip route get 1.1.1.1 → «1.1.1.1 via <шлюз> dev <интерфейс> src <адрес> uid …»
LIVE_ROUTE=$(ip route get 1.1.1.1 2> /dev/null | head -n 1)
route_field() { echo "$LIVE_ROUTE" | tr ' ' '\n' | grep -x -A 1 -- "$1" | sed -n 2p; }
LIVE_DEV=$(route_field dev)
LIVE_SRC=$(route_field src)
LIVE_GW=$(route_field via)
LIVE_TS=$(ip -4 -br addr show tailscale0 2> /dev/null | awk '{print $3}' | cut -d/ -f1)

# --- Git: answers.txt и адреса сервера не должны попасть в репозиторий ---
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
# какие адреса искать: адрес сервера, шлюз и адрес Tailscale — и те, что сейчас у сервера, и те, что в answers.txt
private_ips() {
    local a
    for a in "$LIVE_SRC" "$LIVE_GW" "$LIVE_TS" "$(answer server_ip)" "$(answer gateway)" "$(answer tailscale_ip)"; do
        if is_ipv4 "$a"; then echo "$a"; fi
    done | sort -u
}
# адресов сервера не должно быть ни в файлах репозитория, ни в сообщениях коммитов ветки
check_leaks() {
    local a ips leaks=0
    ips=$(private_ips)
    if [ -z "$ips" ]; then
        note "утечку адресов проверю, когда сервер покажет свой адрес и шлюз (ip route get 1.1.1.1)"
        return
    fi
    for a in $ips; do
        if git grep -q -F -w -e "$a" -- . ../../README.md ':(exclude)check_task41.sh' ':(exclude)answers.txt' 2> /dev/null; then
            bad "адрес сервера есть в файлах репозитория: $(git grep -l -F -w -e "$a" -- . ../../README.md ':(exclude)check_task41.sh' ':(exclude)answers.txt' | tr '\n' ' ')— убери его: скрипт сам находит шлюз. Если уже запушено — напиши мне"
            leaks=1
        fi
        if git log --format='%B' main..HEAD 2> /dev/null | grep -q -F -w -e "$a"; then
            bad "адрес сервера есть в сообщении коммита ветки task41 — напиши мне, поправим историю"
            leaks=1
        fi
    done
    if [ "$leaks" -eq 0 ]; then ok "адресов сервера нет ни в файлах репозитория, ни в сообщениях коммитов"; fi
}


# --- «учебная сеть»: заглушки ip и ping ---
FAKEBIN="$TMP/fakebin"
FAKE_GW=192.0.2.1
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/ip" <<'SH'
#!/bin/bash
# Заглушка ip для проверки Задачи 41: таблица маршрутов учебного сервера.
# Два маршрута по умолчанию: Wi-Fi (metric 600) и запасной кабель (metric 700).
# FAKE_NO_DEFAULT=1 — маршрутов по умолчанию нет.
case " $* " in
    *" get "*)
        echo "1.1.1.1 via 192.0.2.1 dev wlx0 src 192.0.2.50 uid 1000"
        echo "    cache"
        exit 0 ;;
esac
if [ "$FAKE_NO_DEFAULT" != "1" ]; then
    echo "default via 192.0.2.1 dev wlx0 proto dhcp src 192.0.2.50 metric 600 "
    echo "default via 198.51.100.1 dev enx1 proto dhcp src 198.51.100.50 metric 700 "
fi
case " $* " in
    *" default "*) ;;
    *)
        echo "172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown "
        echo "192.0.2.0/24 dev wlx0 proto kernel scope link src 192.0.2.50 metric 600 "
        echo "198.51.100.0/24 dev enx1 proto kernel scope link src 198.51.100.50 metric 700 " ;;
esac
exit 0
SH
cat > "$FAKEBIN/ping" <<'SH'
#!/bin/bash
# Заглушка ping для проверки Задачи 41: ничего не отправляет.
# FAKE_DOWN — адреса и имена, которые «не отвечают» (код 1),
# FAKE_NOHOST — имена, которые «не находятся» (код 2, как при сломанном DNS).
args="$*"
echo "${args//$'\n'/\\n}" >> "$FAKE_LOG"
if [ "$#" -eq 0 ]; then echo "ping: usage error: Destination address required" >&2; exit 2; fi
target="${!#}"
for t in $FAKE_DOWN; do
    if [ "$target" == "$t" ]; then
        echo "PING $target ($target) 56(84) bytes of data."
        echo
        echo "--- $target ping statistics ---"
        echo "1 packets transmitted, 0 received, 100% packet loss, time 0ms"
        echo
        exit 1
    fi
done
for t in $FAKE_NOHOST; do
    if [ "$target" == "$t" ]; then
        echo "ping: $target: Temporary failure in name resolution" >&2
        exit 2
    fi
done
case "$target" in
    "" | *" "* | *$'\n'* | -*)
        echo "ping: $target: Name or service not known" >&2
        exit 2 ;;
esac
echo "PING $target ($target) 56(84) bytes of data."
echo "64 bytes from $target: icmp_seq=1 ttl=57 time=12.3 ms"
echo
echo "--- $target ping statistics ---"
echo "1 packets transmitted, 1 received, 0% packet loss, time 0ms"
echo "rtt min/avg/max/mdev = 12.300/12.300/12.300/0.000 ms"
exit 0
SH
chmod +x "$FAKEBIN/ip" "$FAKEBIN/ping"


# --- net_diag.sh ---
SCRIPT=./net_diag.sh
# need_script N — файл есть и запускается; для шага 3 — ещё переменные internet_ip и internet_name
need_script() {
    local f=net_diag.sh
    if [ ! -f "$f" ]; then bad "нет файла $f в папке задачи"; return 1; fi
    if [ ! -x "$f" ]; then bad "$f не запускается как программа — нет права x (chmod +x в WSL, коммит, push, pull)"; return 1; fi
    if grep -q $'\r' "$f"; then bad "$f: Windows-переводы строк (^M) — в VS Code внизу справа CRLF → LF"; return 1; fi
    if [ "$(head -n 1 "$f")" != "#!/bin/bash" ]; then bad "$f: первая строка не #!/bin/bash"; return 1; fi
    if [ "$(grep -c '^max_wait=' "$f")" -ne 1 ]; then bad "$f: нужна одна строка, которая начинается с max_wait= (сколько секунд ждать ответ)"; return 1; fi
    if grep -Eq '/(usr/)?s?bin/(ping|ip)([^a-z_]|$)' "$f"; then
        bad "$f: ping и ip вызывай по имени, без пути (/usr/bin/…): иначе проверка не сможет подложить свои заглушки"
        return 1
    fi
    if [ "$1" == "3" ]; then
        if [ "$(grep -c '^internet_ip=' "$f")" -ne 1 ] || [ "$(grep -c '^internet_name=' "$f")" -ne 1 ]; then
            bad "$f: нужны строки internet_ip=… и internet_name=… — по одной (шаг 3)"
            return 1
        fi
    fi
    return 0
}

# run_fake [ПЕРЕМЕННАЯ=значение для заглушек …] → OUT, ERR, CODE, CALLS (по строке на вызов ping)
RUN_MODE=fake
run_fake() {
    RUN_MODE=fake
    : > "$TMP/ping.log"
    env PATH="$FAKEBIN:$PATH" FAKE_LOG="$TMP/ping.log" "$@" \
        timeout 20 "$SCRIPT" > "$TMP/out" 2> "$TMP/err" < /dev/null
    CODE=$?
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
    CALLS=$(cat "$TMP/ping.log")
}
# run_real → то же, но по-настоящему: настоящие ip и ping, сеть сервера
run_real() {
    RUN_MODE=real
    timeout 30 "$SCRIPT" > "$TMP/out" 2> "$TMP/err" < /dev/null
    CODE=$?
    OUT=$(cat "$TMP/out")
    ERR=$(cat "$TMP/err")
    CALLS=""
}
calls_count() { if [ -z "$CALLS" ]; then echo 0; else echo "$CALLS" | wc -l; fi; }
# цель вызова ping номер N — последнее слово строки
call_target() { echo "$CALLS" | sed -n "${1}p" | awk '{print $NF}'; }
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
    if [ "$CODE" -eq 124 ]; then hint "скрипт не закончился вовремя — что-то ждёт ввода или висит. У ping есть -c 1?"; fi
    if [[ "$OUT" == *"bytes of data"* || "$OUT" == *"packet loss"* ]]; then
        hint "в выводе скрипта — текст самого ping. Его нужно выбросить: > /dev/null (урок 07)"
    fi
    if [[ "$ERR" == *"name resolution"* || "$ERR" == *"Name or service"* ]]; then
        hint "в stderr — сообщение ping об ошибке. Ошибки ping тоже выброси: 2>&1 после > /dev/null (урок 07)"
    fi
    if [ "$RUN_MODE" == "fake" ] && [ "$CODE" -ne 124 ] && [ "$(calls_count)" -eq 0 ] && [ -n "$OUT" ] \
        && [[ "$OUT" != "CRITICAL: no default gateway"* ]]; then
        hint "заглушка ping ни разу не вызвалась — ping в скрипте вызывается по имени? Проверка подставляет свою команду ping"
    fi
    if [[ "$(call_target 1)" == *'\n'* ]]; then
        hint "в переменной шлюза две строки: у учебного сервера два маршрута по умолчанию. Бери первый: head -n 1 перед cut"
    fi
    if [[ "$OUT" == *"gateway via "* || "$OUT" == *"gateway default "* || "$OUT" == *"gateway dev "* ]]; then
        hint "в переменной шлюза не адрес, а слово из строки маршрута — посчитай, какое по счёту слово адрес (cut -f)"
    fi
}

# expect_fake что_проверяем ждём_вывод ждём_код [подсказка]  (после run_fake)
expect() {
    if [ "$OUT" == "$2" ] && [ "$CODE" -eq "$3" ] && [ -z "$ERR" ]; then
        ok "$1: код $CODE"
        return 0
    fi
    bad "$1: ждём «${2//$'\n'/ ⏎ }» и код $3; сейчас: «$(show "$OUT")», код $CODE${ERR:+, в stderr: «$(show "$ERR")»}"
    explain
    if [ "$OUT" == "$2" ] && [ -n "$ERR" ]; then hint "вывод и код верные, но в stderr что-то есть — там должно быть пусто"
    elif [ "$OUT" == "$2" ]; then hint "вывод верный, а код выхода нет: OK — 0, CRITICAL — 2"
    else
        # первая строка, которая не совпала
        local i=1 e a total
        total=$(echo "$2" | wc -l)
        while [ "$i" -le "$total" ]; do
            e=$(echo "$2" | sed -n "${i}p")
            a=$(line_n "$i")
            if [ "$e" != "$a" ]; then break; fi
            i=$((i + 1))
        done
        if [ "$i" -gt "$total" ]; then hint "лишние строки после «$(echo "$2" | tail -n 1)» — после CRITICAL нужен exit 2, а в конце больше ничего не печатаем"
        elif [ "$i" -eq "$total" ] && [ -n "$4" ] && [[ "$a" == "${e%% *}"* ]]; then hint "$4"
        else hint "строка $i не совпала: ждём «$e», сейчас «$a» — сравни буква в букву"; fi
    fi
    return 1
}

# все вызовы ping: один пакет (-c 1) и ожидание из max_wait (-W или -w)
check_ping_flags() {
    local wait=$1 line bad_c=0 bad_w=0
    local re_c='(^| )-c ?1( |$)'
    local re_w="(^| )-[Ww] ?$wait( |$)"
    if [ -z "$CALLS" ]; then return; fi
    while IFS= read -r line; do
        if ! [[ "$line" =~ $re_c ]]; then bad_c=1; fi
        if ! [[ "$line" =~ $re_w ]]; then bad_w=1; fi
    done <<< "$CALLS"
    if [ "$bad_c" -eq 0 ]; then ok "каждый ping — один пакет (-c 1)"
    else bad "не у каждого ping есть -c 1 (один пакет). Без -c ping не останавливается. Вызовы: «${CALLS//$'\n'/ | }»"; fi
    if [ "$bad_w" -eq 0 ]; then ok "каждый ping ждёт ответ не дольше max_wait ($wait с)"
    else bad "не у каждого ping ожидание ответа из \$max_wait (с max_wait=$wait ждём флаг со значением $wait — тот, что нашёл 🔎). Вызовы: «${CALLS//$'\n'/ | }»"; fi
}


# ---------------------------------------------------------------
if run_step 1; then
    echo "Шаг 1. Сеть сервера"
    if need_answers; then
        check_answers_ignored
        if [ -z "$LIVE_DEV" ] || [ -z "$LIVE_SRC" ]; then
            bad "ip route get 1.1.1.1 ничего понятного не показал — у сервера сейчас нет маршрута в интернет? Напиши мне"
        fi

        v=$(answer main_interface)
        if [ -z "$v" ]; then bad "main_interface: пусто — ждём имя интерфейса (как в первой колонке ip -br addr)"
        elif [ "$v" == "$LIVE_DEV" ]; then ok "main_interface: $v"
        elif [ "$v" == "lo" ] || [ "$v" == "tailscale0" ] || [[ "$v" == docker* || "$v" == br-* || "$v" == veth* ]]; then
            bad "main_interface: $v — это не тот, через который сервер ходит в интернет. Спроси систему: ip route get 1.1.1.1, слово после dev"
        else bad "main_interface: «$v», а ip route get 1.1.1.1 показывает другой — слово после dev"; fi

        v=$(answer server_ip)
        if [ -z "$v" ]; then bad "server_ip: пусто"
        elif [[ "$v" == */* ]]; then bad "server_ip: «$v» — без /… : адрес — то, что до косой черты"
        elif [ "$v" == "$LIVE_SRC" ]; then ok "server_ip: адрес сервера на $LIVE_DEV верный"
        elif [ "$v" == "$LIVE_TS" ]; then bad "server_ip: это адрес Tailscale (tailscale0), а нужен адрес на интерфейсе, через который сервер ходит в интернет"
        else bad "server_ip: «$v» не совпадает с адресом сервера на $LIVE_DEV — в ip route get 1.1.1.1 это слово после src"; fi

        v=$(answer gateway)
        if [ -z "$LIVE_GW" ]; then note "у маршрута к 1.1.1.1 нет шлюза (via) — так бывает с VPN. gateway не проверяю, напиши мне"
        elif [ -z "$v" ]; then bad "gateway: пусто"
        elif [ "$v" == "$LIVE_GW" ]; then ok "gateway: шлюз верный"
        elif [ "$v" == "$LIVE_SRC" ]; then bad "gateway: это адрес самого сервера (src), а шлюз — слово после via"
        else bad "gateway: «$v» не совпадает со шлюзом — в ip route get 1.1.1.1 это слово после via (и в ip route — в строке default)"; fi

        v=$(answer tailscale_ip)
        if [ -z "$LIVE_TS" ]; then note "интерфейса tailscale0 с IPv4-адресом на сервере сейчас нет — tailscale_ip не проверяю"
        elif [ -z "$v" ]; then bad "tailscale_ip: пусто — ждём IPv4-адрес из строки tailscale0 в ip -br addr"
        elif [[ "$v" == */* ]]; then bad "tailscale_ip: «$v» — без /32: адрес — то, что до косой черты"
        elif [[ "$v" == *:* ]]; then bad "tailscale_ip: это IPv6-адрес (с двоеточиями), а нужен IPv4 — четыре числа через точку"
        elif [ "$v" == "$LIVE_TS" ]; then ok "tailscale_ip: адрес Tailscale верный"
        else bad "tailscale_ip: «$v» не совпадает с IPv4-адресом на tailscale0"; fi

        v=$(answer first_hop)
        if [ -z "$v" ]; then bad "first_hop: пусто — ждём адрес со строки «1:» в выводе tracepath -n"
        elif [ "$v" == "none" ]; then note "first_hop: none — первый маршрутизатор не ответил tracepath. Так бывает, засчитано"; PASS=$((PASS + 1))
        elif [ "$v" == "$LIVE_GW" ]; then ok "first_hop: совпадает со шлюзом — первый хоп и есть шлюз"
        elif [[ "$v" == *LOCALHOST* || "$v" == "$LIVE_SRC" ]]; then bad "first_hop: это строка «1?:» — сам сервер. Нужен адрес на строке «1:»"
        elif ! is_ipv4 "$v"; then bad "first_hop: «$v» — ждём адрес (четыре числа через точку). tracepath запускай с -n, тогда вместо имён будут адреса"
        else bad "first_hop: «$v», а шлюз сервера другой. Первый хоп — обычно шлюз: сравни строку «1:» с gateway. Если уверен в ответе — напиши мне"; fi

        v=$(answer hops)
        if [ -z "$v" ]; then bad "hops: пусто — ждём число из строки Resume (слово после hops)"
        elif [ "$v" == "none" ]; then note "hops: none — tracepath не дошёл до 1.1.1.1 (нет reached). Засчитано, но интересно, на каком хопе обрыв — расскажи"; PASS=$((PASS + 1))
        elif ! is_int "$v"; then bad "hops: «$v» — ждём число или none"
        elif [ "$v" -eq 1 ]; then bad "hops: 1 — это был бы только шлюз. До 1.1.1.1 хопов больше: смотри строку Resume в самом конце"
        elif [ "$v" -ge 2 ] && [ "$v" -le 30 ]; then ok "hops: $v"
        else bad "hops: $v — tracepath считает не больше 30 хопов. Число — из строки Resume (слово после hops)"; fi
    fi
fi

if run_step 2; then
    echo "Шаг 2. net_diag.sh — шлюз"
    if need_script 2; then
        if grep -q '^max_wait=2$' net_diag.sh; then ok "max_wait=2"
        else bad "строка max_wait должна быть ровно max_wait=2 (2 секунды, без пробелов у =)"; fi

        # Шлюз отвечает. В учебной сети два маршрута по умолчанию — берём первый.
        run_fake
        first=$(line_n 1)
        if [ "$first" == "OK: gateway $FAKE_GW replies" ] && [ "$CODE" -eq 0 ] && [ -z "$ERR" ]; then
            ok "шлюз отвечает: «$first», код 0"
        else
            bad "шлюз отвечает: первая строка — «OK: gateway $FAKE_GW replies», код 0; сейчас: «$(show "$OUT")», код $CODE${ERR:+, в stderr: «$(show "$ERR")»}"
            explain
            hint "формат — буква в букву: «OK: gateway <адрес> replies»"
        fi
        if [ "$(call_target 1)" == "$FAKE_GW" ]; then ok "первый ping — к шлюзу из маршрута по умолчанию"
        elif [ -n "$CALLS" ]; then bad "первый ping ушёл к «$(call_target 1)», а шлюз учебного сервера — $FAKE_GW"; fi
        check_ping_flags 2

        # max_wait берётся из переменной: копия скрипта с max_wait=1
        sed 's/^max_wait=.*/max_wait=1/' net_diag.sh > "$TMP/net_diag_wait1.sh"
        chmod +x "$TMP/net_diag_wait1.sh"
        SCRIPT="$TMP/net_diag_wait1.sh"
        run_fake
        SCRIPT=./net_diag.sh
        re_w1='(^| )-[Ww] ?1( |$)'
        if [[ "$(echo "$CALLS" | head -n 1)" =~ $re_w1 ]]; then ok "с max_wait=1 ping ждёт 1 секунду — число берётся из переменной"
        else bad "с max_wait=1 ping вызван так: «$(echo "$CALLS" | head -n 1)» — время ожидания не из \$max_wait?"; fi

        # Шлюз молчит
        run_fake FAKE_DOWN="$FAKE_GW"
        if [ "$(line_n 1)" == "OK: gateway $FAKE_GW replies" ]; then
            hint "шлюз молчит (ping вернул 1), а скрипт пишет OK — код выхода ping не дошёл до if. Сохраняй его сразу следующей строкой после ping: code=\$? (урок 12)"
        fi
        expect "шлюз не отвечает" "CRITICAL: gateway $FAKE_GW does not reply - local network problem" 2 \
            "шлюз молчит → одна строка CRITICAL и сразу exit 2: дальше проверять нет смысла"
        if [ "$(calls_count)" -gt 1 ]; then bad "после молчащего шлюза скрипт пинговал дальше (вызовов ping: $(calls_count)) — должен остановиться (exit 2)"; fi

        # Маршрута по умолчанию нет
        run_fake FAKE_NO_DEFAULT=1
        expect "нет маршрута по умолчанию" "CRITICAL: no default gateway (check: ip route)" 2 \
            "переменная шлюза пустая → проверка [ -z \"\$gateway\" ] до ping, сообщение и exit 2"
        if [ "$(calls_count)" -gt 0 ]; then bad "без маршрута по умолчанию скрипт всё равно вызвал ping («$(echo "$CALLS" | head -n 1)») — пустой шлюз нужно поймать до ping"; fi

        # По-настоящему
        if [ -n "$LIVE_GW" ]; then
            run_real
            first=$(line_n 1)
            if [ "$first" == "OK: gateway $LIVE_GW replies" ] && [ "$CODE" -eq 0 ] && [ -z "$ERR" ]; then
                ok "на сети сервера: шлюз отвечает, код 0"
            else
                bad "на сети сервера ждём первую строку «OK: gateway <шлюз сервера> replies» и код 0; сейчас: «$(show "$OUT")», код $CODE${ERR:+, в stderr: «$(show "$ERR")»}"
                explain
                if [ "$CODE" -eq 124 ]; then hint "настоящий ping без -c не останавливается сам"; fi
                if [[ "$first" == "CRITICAL: gateway"* ]]; then
                    hint "если шлюз сервера правда не отвечает на ping (ping -c 3 <шлюз> руками), а интернет работает — напиши мне"
                fi
            fi
        else note "на сети сервера не проверяю: у маршрута к 1.1.1.1 нет шлюза (via)"; fi
        if [ "$STEP" != "all" ]; then check_leaks; fi
    fi
fi

if run_step 3; then
    echo "Шаг 3. Интернет по адресу и по имени"
    if need_script 3; then
        if grep -q '^internet_ip=1\.1\.1\.1$' net_diag.sh; then ok "internet_ip=1.1.1.1"
        else bad "строка должна быть ровно internet_ip=1.1.1.1"; fi
        if grep -q '^internet_name=one\.one\.one\.one$' net_diag.sh; then ok "internet_name=one.one.one.one"
        else bad "строка должна быть ровно internet_name=one.one.one.one"; fi

        all_ok="OK: gateway $FAKE_GW replies
OK: internet 1.1.1.1 replies
OK: name one.one.one.one resolves and replies"
        run_fake
        if [ "$(line_n 3)" == "CRITICAL: name one.one.one.one resolves but does not reply" ]; then
            hint "имя ответило (ping вернул 0), а скрипт пишет «does not reply». Не проверяешь ли \$? дважды? После первого [ ] в \$? уже код самой проверки [ ], а не ping. Сохрани код ping в переменную сразу после ping"
        fi
        expect "всё работает" "$all_ok" 0 "три строки OK — шлюз, интернет по адресу, по имени — и код 0"
        if [ "$(calls_count)" -eq 3 ]; then check_ping_flags 2
        else bad "ждём 3 вызова ping (шлюз, 1.1.1.1, one.one.one.one), сейчас — $(calls_count): «${CALLS//$'\n'/ | }»"; fi

        run_fake FAKE_DOWN=1.1.1.1
        expect "нет интернета" "OK: gateway $FAKE_GW replies
CRITICAL: internet 1.1.1.1 does not reply - router or provider problem" 2 \
            "интернет по адресу молчит → строка CRITICAL и exit 2, имя уже не проверяем"
        if [ "$(calls_count)" -gt 2 ]; then bad "интернета нет, а скрипт всё равно пинговал имя — после CRITICAL нужен exit 2"; fi

        run_fake FAKE_NOHOST=one.one.one.one
        expect "не работает DNS" "OK: gateway $FAKE_GW replies
OK: internet 1.1.1.1 replies
CRITICAL: name one.one.one.one does not resolve - DNS problem" 2 \
            "имя не нашлось — у ping это код «другая ошибка» (🔎 EXIT STATUS), а не «нет ответа». Не перепутаны ли коды?"

        run_fake FAKE_DOWN=one.one.one.one
        expect "имя есть, но не отвечает" "OK: gateway $FAKE_GW replies
OK: internet 1.1.1.1 replies
CRITICAL: name one.one.one.one resolves but does not reply" 2 \
            "имя нашлось, но ответа нет — у ping это код «ни одного ответа» (🔎 EXIT STATUS). Не перепутаны ли коды?"

        # адрес и имя берутся из переменных: копии скрипта с другими значениями
        sed 's/^internet_ip=.*/internet_ip=203.0.113.7/; s/^internet_name=.*/internet_name=example.test/' net_diag.sh > "$TMP/net_diag_vars.sh"
        chmod +x "$TMP/net_diag_vars.sh"
        SCRIPT="$TMP/net_diag_vars.sh"
        run_fake
        SCRIPT=./net_diag.sh
        if [ "$(line_n 2)" == "OK: internet 203.0.113.7 replies" ] && [ "$(call_target 2)" == "203.0.113.7" ]; then
            ok "с internet_ip=203.0.113.7 пингуется он — адрес берётся из переменной"
        else bad "с internet_ip=203.0.113.7 ждём строку «OK: internet 203.0.113.7 replies» и ping к нему; сейчас: «$(line_n 2)», ping к «$(call_target 2)»"; fi
        if [ "$(line_n 3)" == "OK: name example.test resolves and replies" ] && [ "$(call_target 3)" == "example.test" ]; then
            ok "с internet_name=example.test пингуется оно — имя берётся из переменной"
        else bad "с internet_name=example.test ждём строку «OK: name example.test resolves and replies» и ping к нему; сейчас: «$(line_n 3)», ping к «$(call_target 3)»"; fi

        # По-настоящему
        if [ -n "$LIVE_GW" ]; then
            run_real
            expect "на сети сервера" "OK: gateway $LIVE_GW replies
OK: internet 1.1.1.1 replies
OK: name one.one.one.one resolves and replies" 0 \
                "если сеть сервера сейчас правда сломана — проверь руками ping -c 3 1.1.1.1 и ping -c 3 one.one.one.one и напиши мне"
        else note "на сети сервера не проверяю: у маршрута к 1.1.1.1 нет шлюза (via)"; fi
        if [ "$STEP" != "all" ]; then check_leaks; fi
    fi
fi

if run_step 4; then
    echo "Шаг 4. Git и README"
    for f in .gitignore net_diag.sh; do
        if in_git "$f"; then ok "$f добавлен в Git"
        else bad "$f не добавлен в Git (git add)"; fi
    done
    if [ -f answers.txt ]; then check_answers_ignored
    else bad "нет answers.txt на сервере, в папке задачи (шаг 1)"; fi
    if [ -n "$(git log --oneline main..HEAD -- answers.txt 2> /dev/null)" ]; then
        bad "answers.txt есть в истории ветки task41 (в одном из коммитов) — напиши мне, уберём"
    fi
    check_leaks
    if grep -q '`day26/`' ../../README.md 2> /dev/null; then ok "в README есть строка для day26/"
    else bad "в README (корень репозитория) нет строки для \`day26/\` в таблице Structure"; fi
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
