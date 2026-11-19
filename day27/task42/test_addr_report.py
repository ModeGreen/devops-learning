# Тест к Задаче 42. Запуск из папки задачи (day27/task42):
#   python3 test_addr_report.py      — все шаги (на сервере)
#   python3 test_addr_report.py 2    — только шаг 2 (и так же 1…4)
# Шаги 2–3 работают и в WSL, и на сервере. Шаги 1 и 4 — только на сервере: там лежит answers.txt.
#
# addr_report.py запускается двумя способами:
#   - с «учебным» ip: на время запуска тест подкладывает заглушку ip (во временной папке, первой в PATH).
#     Она ничего не спрашивает у системы, а печатает заготовленный вывод ip -j addr учебного сервера;
#   - по-настоящему: с настоящим ip, на адресах этой машины (в WSL — адреса WSL, на сервере — сервера).
# answers.txt живёт только на сервере: тест следит, чтобы ни он, ни адреса сервера не попали в Git.
# Твои файлы тест не меняет. В интернет ходит один раз — в шаге 1 (curl к icanhazip.com).
import contextlib
import importlib.util
import io
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "addr_report.py"
ANSWERS = HERE / "answers.txt"
README = HERE.parent.parent / "README.md"
step = int(sys.argv[1]) if len(sys.argv) > 1 else 0   # 0 = все шаги


# ---------- учебный сервер: вывод ip -j addr ----------
def inet(local, prefixlen, label, scope="global", secondary=False):
    a = {"family": "inet", "local": local, "prefixlen": prefixlen}
    net = ipaddress.ip_interface(f"{local}/{prefixlen}").network
    if prefixlen < 31:
        a["broadcast"] = str(net.broadcast_address)
    a["scope"] = scope
    if secondary:
        a["secondary"] = True
    a.update({"label": label, "valid_life_time": 4294967295, "preferred_life_time": 4294967295})
    return a


def inet6(local, prefixlen, scope="global"):
    return {"family": "inet6", "local": local, "prefixlen": prefixlen, "scope": scope,
            "valid_life_time": 4294967295, "preferred_life_time": 4294967295}


def iface(index, name, state, addrs, link_type="ether"):
    flags = ["LOOPBACK", "UP", "LOWER_UP"] if name == "lo" else \
        (["BROADCAST", "MULTICAST"] if state == "DOWN" else ["BROADCAST", "MULTICAST", "UP", "LOWER_UP"])
    return {"ifindex": index, "ifname": name, "flags": flags, "mtu": 65536 if name == "lo" else 1500,
            "qdisc": "noqueue", "operstate": state, "group": "default", "txqlen": 1000,
            "link_type": "loopback" if name == "lo" else link_type,
            "address": "00:00:00:00:00:00" if name == "lo" else f"02:42:ac:11:00:{index:02x}",
            "broadcast": "00:00:00:00:00:00" if name == "lo" else "ff:ff:ff:ff:ff:ff",
            "addr_info": addrs}


FAKE = [
    iface(1, "lo", "UNKNOWN", [inet("127.0.0.1", 8, "lo", "host"), inet6("::1", 128, "host")]),
    iface(2, "enx1", "DOWN", []),
    iface(3, "wlx0", "UP", [inet("192.168.50.20", 24, "wlx0"),
                            inet("192.168.50.21", 24, "wlx0", secondary=True),
                            inet6("fe80::1c2b:3aff:fe4d:5e6f", 64, "link")]),
    iface(4, "docker0", "UP", [inet("172.17.0.1", 16, "docker0"), inet6("fe80::42:acff:fe11:1", 64, "link")]),
    iface(5, "br-3f1c2a9b7d10", "UP", [inet("172.18.0.1", 16, "br-3f1c2a9b7d10")]),
    iface(6, "veth7a1b2c3", "UP", [inet6("fe80::d8f1:3eff:fe5b:91c4", 64, "link")]),
    iface(7, "tailscale0", "UNKNOWN", [inet("100.101.102.103", 32, "tailscale0"),
                                       inet6("fd7a:115c:a1e0::1234:5678", 128)], link_type="none"),
    iface(8, "eth1", "UP", [inet("169.254.10.20", 16, "eth1", "link")]),
    iface(9, "ens19", "UP", [inet("203.0.113.10", 24, "ens19"), inet6("2001:db8::10", 64)]),
]
FAKE_JSON = json.dumps(FAKE, separators=(",", ":")) + "\n"
FAKE_JSON4 = json.dumps([dict(i, addr_info=[a for a in i["addr_info"] if a["family"] == "inet"])
                         for i in FAKE if any(a["family"] == "inet" for a in i["addr_info"])],
                        separators=(",", ":")) + "\n"
FAKE_PAIRS = [("lo", "127.0.0.1/8"), ("wlx0", "192.168.50.20/24"), ("wlx0", "192.168.50.21/24"),
              ("docker0", "172.17.0.1/16"), ("br-3f1c2a9b7d10", "172.18.0.1/16"),
              ("tailscale0", "100.101.102.103/32"), ("eth1", "169.254.10.20/16"), ("ens19", "203.0.113.10/24")]

# ---------- эталон: та же таблица, что в условии ----------
REF_KINDS = [("127.0.0.0/8", "loopback"), ("169.254.0.0/16", "link-local"), ("10.0.0.0/8", "private"),
             ("172.16.0.0/12", "private"), ("192.168.0.0/16", "private"), ("100.64.0.0/10", "shared")]
REF_NOTES = {"loopback": "this machine only", "link-local": "same link only",
             "private": "not routed on the internet", "shared": "Tailscale or provider CGNAT",
             "public": "routed on the internet"}


def ref_pairs(text):
    pairs = []
    for i in json.loads(text):
        for a in i.get("addr_info", []):
            if a.get("family") == "inet":
                pairs.append((i["ifname"], f"{a['local']}/{a['prefixlen']}"))
    return pairs


def ref_kind(address):
    ip = ipaddress.ip_interface(address).ip
    for net, kind in REF_KINDS:
        if ip in ipaddress.ip_network(net):
            return kind
    return "public"


def ref_line(name, address):
    kind = ref_kind(address)
    return f"{name}: {address} in {ipaddress.ip_interface(address).network} - {kind}, {REF_NOTES[kind]}"


# ---------- запуск addr_report.py ----------
CYRILLIC = re.compile("[а-яА-ЯёЁ]")


def need_script():
    assert SCRIPT.exists(), f"нет файла addr_report.py рядом с тестом ({HERE}) — запускай тест из папки задачи"


def load():
    """addr_report.py как модуль — чтобы вызывать его функции по одной."""
    need_script()
    spec = importlib.util.spec_from_file_location("addr_report_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            spec.loader.exec_module(mod)
    except SyntaxError as e:
        raise AssertionError(f"в addr_report.py синтаксическая ошибка: строка {e.lineno}: {e.msg}")
    except SystemExit:
        raise AssertionError("addr_report.py при импорте вызывает main() или sys.exit() — "
                             "main() запускай только внизу: if __name__ == \"__main__\":")
    except Exception as e:
        raise AssertionError(f"addr_report.py не импортируется: {type(e).__name__}: {e}")
    if out.getvalue():
        raise AssertionError("addr_report.py что-то печатает уже при импорте — main() вызывается без "
                             "if __name__ == \"__main__\": (урок Python 05)")
    return mod


def func(mod, name):
    f = getattr(mod, name, None)
    assert callable(f), f"в addr_report.py нет функции {name}()"
    return f


# известные ошибки → подсказка
ERROR_HINTS = [
    ("has no attribute 'read'", "json.load читает файл, а для строки с JSON — json.loads (урок Python 10)"),
    ('can only concatenate str (not "int")', "prefixlen — число, а не строка: собери \"адрес/префикс\" f-строкой"),
    ("No such file or directory: 'ip -j", "subprocess.run получает команду списком слов: [\"ip\", \"-j\", \"addr\"] (урок Python 07)"),
    ("string indices must be integers", "в этом месте строка, а не словарь — json.loads сделан? И цикл идёт по списку интерфейсов, "
                                        "а внутри — по их addr_info?"),
]


def short(a):
    r = repr(a)
    return r if len(r) <= 60 else "<вывод ip -j addr>"


def call(mod, name, *args):
    f = func(mod, name)
    try:
        return f(*args)
    except AssertionError:
        raise
    except Exception as e:
        tb = traceback.extract_tb(e.__traceback__)[-1]
        where = f" (строка {tb.lineno}: {tb.line})" if tb.filename == str(SCRIPT) else ""
        msg = f"{name}({', '.join(short(a) for a in args)}) упала: {type(e).__name__}: {e}{where}"
        for sub, hint in ERROR_HINTS:
            if sub in str(e):
                msg += f"\n  {hint}"
                break
        raise AssertionError(msg)


class FakeIp:
    """Папка с заглушкой ip. log() — с какими аргументами её вызывали."""

    def __enter__(self):
        self.dir = Path(tempfile.mkdtemp(prefix="task42-"))
        (self.dir / "addr.json").write_text(FAKE_JSON, encoding="utf-8")
        (self.dir / "addr4.json").write_text(FAKE_JSON4, encoding="utf-8")
        stub = self.dir / "ip"
        stub.write_text("""#!/bin/bash
# Заглушка ip для теста Задачи 42: печатает вывод ip -j addr учебного сервера.
d="$(dirname "$0")"
echo "$*" >> "$d/calls.log"
json=0; addr=0; v4=0; other=""
for a in "$@"; do
    case "$a" in
        -j|-json|--json) json=1 ;;
        -4) v4=1 ;;
        a|addr|address) addr=1 ;;
        -p|-pretty|--pretty|show) ;;
        *) other="$other $a" ;;
    esac
done
if [ "$json" -eq 1 ] && [ "$addr" -eq 1 ] && [ -z "$other" ]; then
    if [ "$v4" -eq 1 ]; then cat "$d/addr4.json"; else cat "$d/addr.json"; fi
    exit 0
fi
echo "Заглушка ip (тест Задачи 42) умеет только ip -j addr, а вызвали: ip $*" >&2
exit 255
""", encoding="utf-8", newline="\n")
        stub.chmod(0o755)
        self.path = f"{self.dir}{os.pathsep}{os.environ.get('PATH', '')}"
        return self

    def log(self):
        p = self.dir / "calls.log"
        return p.read_text(encoding="utf-8").splitlines() if p.exists() else []

    def __exit__(self, *exc):
        shutil.rmtree(self.dir, ignore_errors=True)


def run_script(path_env=None):
    """python3 addr_report.py → (код, stdout, stderr). path_env — свой PATH (с заглушкой ip)."""
    need_script()
    env = dict(os.environ)
    if path_env:
        env["PATH"] = path_env
    try:
        r = subprocess.run([sys.executable, str(SCRIPT)], cwd=HERE, env=env, capture_output=True,
                           text=True, timeout=20, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise AssertionError("python3 addr_report.py не закончился за 20 секунд — что-то ждёт ввода или висит")
    return r.returncode, r.stdout, r.stderr


def show(text, limit=600):
    text = text.rstrip("\n")
    return text if len(text) <= limit else text[:limit] + " …"


def last_error(err):
    lines = [l for l in err.strip().splitlines() if l.strip()]
    return lines[-1] if lines else ""


def real_ip_json():
    """Настоящий ip -j addr этой машины или None, если ip нет."""
    if not shutil.which("ip"):
        return None
    r = subprocess.run(["ip", "-j", "addr"], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return r.stdout


# ---------- что сервер показывает прямо сейчас ----------
def live_route():
    """(интерфейс, адрес сервера, шлюз) маршрута к 1.1.1.1 или (None, None, None)."""
    if not shutil.which("ip"):
        return None, None, None
    r = subprocess.run(["ip", "-j", "route", "get", "1.1.1.1"], capture_output=True, text=True)
    try:
        route = json.loads(r.stdout)[0]
        return route.get("dev"), route.get("prefsrc"), route.get("gateway")
    except (ValueError, IndexError, KeyError, TypeError):
        pass
    r = subprocess.run(["ip", "route", "get", "1.1.1.1"], capture_output=True, text=True)
    words = r.stdout.split()

    def after(w):
        return words[words.index(w) + 1] if w in words and words.index(w) + 1 < len(words) else None
    return after("dev"), after("src"), after("via")


def live_iface_inet(dev):
    """IPv4-адреса интерфейса dev: список строк «адрес/префикс»."""
    if not dev or not shutil.which("ip"):
        return []
    r = subprocess.run(["ip", "-j", "addr", "show", "dev", dev], capture_output=True, text=True)
    try:
        return [f"{a['local']}/{a['prefixlen']}" for i in json.loads(r.stdout)
                for a in i.get("addr_info", []) if a.get("family") == "inet"]
    except (ValueError, KeyError, TypeError):
        return []


def answers():
    """answers.txt → словарь «ключ: значение». На сервере, в папке задачи."""
    assert ANSWERS.exists(), "нет answers.txt в папке задачи. Шаги 1 и 4 — только на сервере: " \
                             "там answers.txt пишется в nano (шаг 1). В WSL запускай шаги 2 и 3"
    d = {}
    for line in ANSWERS.read_text(encoding="utf-8").splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            d.setdefault(k.strip(), v.strip())
    return d


def git(*args):
    return subprocess.run(["git", *args], cwd=HERE, capture_output=True, text=True)


def in_git(name):
    return git("ls-files", "--error-unmatch", name).returncode == 0


def check_answers_ignored():
    assert not in_git("answers.txt"), "answers.txt добавлен в Git, а он должен остаться только на сервере — напиши мне, уберём"
    assert git("check-ignore", "-q", "answers.txt").returncode == 0, \
        "answers.txt не игнорируется: нужен .gitignore со строкой answers.txt в папке задачи (подготовка), на сервере — git pull"


def private_values():
    """Что не должно попасть в репозиторий: адрес сервера, шлюз, адрес Tailscale, сеть и публичный адрес."""
    vals = set()
    dev, src, gw = live_route()
    for v in (src, gw):
        if v:
            vals.add(v)
    for a in live_iface_inet("tailscale0"):
        vals.add(a.split("/")[0])
    if ANSWERS.exists():
        a = answers()
        for k in ("lan_network", "public_ip"):
            if a.get(k):
                vals.add(a[k])
    if src:
        for a in live_iface_inet(dev):
            if a.split("/")[0] == src:
                vals.add(str(ipaddress.ip_interface(a).network))
    return {v for v in vals if re.fullmatch(r"[0-9.]+(/[0-9]+)?", v)}


def check_leaks():
    """Адресов сервера нет ни в файлах репозитория (папка задачи и README), ни в сообщениях коммитов ветки."""
    vals = private_values()
    if not vals:
        print("  ℹ️  утечку адресов проверю на сервере, когда там есть answers.txt и маршрут к 1.1.1.1")
        return
    files = [f for f in git("ls-files", "--", ".", str(README)).stdout.splitlines()
             if Path(f).name not in ("test_addr_report.py", "answers.txt")]
    log = git("log", "--format=%B", "main..HEAD").stdout
    for v in vals:
        pat = re.compile(r"(?<![0-9.])" + re.escape(v) + r"(?![0-9])")
        for f in files:
            p = HERE / f
            if p.is_file() and pat.search(p.read_text(encoding="utf-8", errors="ignore")):
                raise AssertionError(f"в {f} есть адрес или сеть твоего сервера — в публичный репозиторий их не пишем "
                                     "(п. 18). Скрипт читает адреса при запуске. Если уже запушено — напиши мне")
        if pat.search(log):
            raise AssertionError("адрес или сеть твоего сервера есть в сообщении коммита ветки — напиши мне, поправим историю")
    print("  ✅ адресов сервера нет ни в файлах репозитория, ни в сообщениях коммитов")


# ---------- шаги ----------
def check_step1():
    a = answers()
    check_answers_ignored()
    dev, src, gw = live_route()
    assert dev and src, "ip route get 1.1.1.1 ничего понятного не показал — у сервера сейчас нет маршрута в интернет? Напиши мне"
    mine = [x for x in live_iface_inet(dev) if x.split("/")[0] == src]
    assert mine, f"не нашёл адрес {src} на интерфейсе {dev} в ip -j addr — напиши мне"
    live = ipaddress.ip_interface(mine[0])
    net = live.network
    problems = []

    def ok(msg):
        print(f"  ✅ {msg}")

    def bad(msg):
        print(f"  ❌ {msg}")
        problems.append(msg)

    # lan_network
    v = a.get("lan_network", "")
    if not v or "<" in v:
        bad("lan_network: пусто или осталась заготовка <…> — ждём сеть главного интерфейса: адрес сети/префикс")
    elif "/" not in v:
        bad(f"lan_network: «{v}» — без префикса. Сеть пишется как адрес сети/префикс, например 10.20.0.0/24")
    else:
        try:
            got = ipaddress.ip_network(v)
        except ValueError:
            try:
                loose = ipaddress.ip_network(v, strict=False)
            except ValueError:
                bad(f"lan_network: «{v}» — не похоже на сеть: четыре числа через точку, косая черта, префикс")
            else:
                if loose == net:
                    bad(f"lan_network: «{v}» — это адрес с префиксом, а сеть пишется с нулями в части узла (урок, часть 1)")
                else:
                    bad(f"lan_network: «{v}» — в части узла не нули, и это не сеть {dev}. Сеть — адрес сервера с нулями в части узла")
        else:
            if got == net:
                ok(f"lan_network: {v}")
            elif got.prefixlen != net.prefixlen:
                bad(f"lan_network: префикс /{got.prefixlen}, а у адреса сервера на {dev} — другой. Сверься с ip -br addr")
            else:
                bad(f"lan_network: «{v}» не совпадает с сетью главного интерфейса {dev}. "
                    "Сверься с ip route: строка без via с этим интерфейсом")

    # netmask
    v = a.get("netmask", "")
    if not v or "<" in v:
        bad("netmask: пусто или осталась заготовка <…> — ждём маску четырьмя числами через точку")
    elif v.lstrip("/").isdigit():
        bad(f"netmask: «{v}» — это префикс, а маска пишется четырьмя числами, как 255.255.255.0 (урок, часть 2)")
    elif v == str(net.netmask):
        ok(f"netmask: {v}")
    else:
        bad(f"netmask: «{v}» — не та маска для /{net.prefixlen}. Таблица — урок, часть 2")

    # lan_hosts
    v = a.get("lan_hosts", "")
    want = net.num_addresses - 2 if net.prefixlen <= 30 else net.num_addresses
    if not v.isdigit():
        bad(f"lan_hosts: «{v}» — ждём число")
    elif int(v) == want:
        ok(f"lan_hosts: {v}")
    elif int(v) == net.num_addresses:
        bad(f"lan_hosts: {v} — это все адреса сети, а устройствам на 2 меньше: адрес сети и broadcast заняты")
    else:
        bad(f"lan_hosts: {v} — для /{net.prefixlen} не так. Адресов — 2 в степени (32 − префикс), устройствам — на 2 меньше")

    # public_ip
    v = a.get("public_ip", "")
    live_public = None
    if shutil.which("curl"):
        r = subprocess.run(["curl", "-4", "-s", "--max-time", "8", "https://icanhazip.com"],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            live_public = r.stdout.strip()
    if not v or "<" in v:
        bad("public_ip: пусто или осталась заготовка <…> — ждём адрес, который ответил icanhazip.com")
    elif ":" in v:
        bad("public_ip: это IPv6-адрес (с двоеточиями). Нужен IPv4 — у curl для этого есть флаг (🔎)")
    elif not re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", v):
        bad(f"public_ip: «{v}» — ждём адрес: четыре числа через точку")
    elif v == src:
        bad("public_ip: это адрес сервера в локальной сети. Публичный — тот, что отвечает curl … https://icanhazip.com")
    elif live_public is None:
        print(f"  ℹ️  public_ip: {v} — не смог спросить icanhazip.com, проверил только вид адреса")
    elif v == live_public:
        ok("public_ip: совпадает с тем, что сейчас отвечает icanhazip.com")
    else:
        bad(f"public_ip: «{v}», а icanhazip.com сейчас отвечает {live_public}. У домашнего интернета публичный адрес "
            "иногда меняется — запусти curl ещё раз и сравни")

    # behind_nat
    v = a.get("behind_nat", "").lower()
    public = live_public or a.get("public_ip", "")
    want = "yes" if public != src else "no"
    if v not in ("yes", "no"):
        bad(f"behind_nat: «{a.get('behind_nat', '')}» — ждём yes или no")
    elif v == want:
        ok(f"behind_nat: {v}")
    else:
        bad(f"behind_nat: {v} — сравни public_ip с адресом сервера на {dev} (урок, часть 4)")

    assert not problems, f"не сошлось ответов: {len(problems)} — строки с ❌ выше"
    print("Шаг 1 ✅ сеть, маска, размер сети, публичный адрес и NAT")


def check_parse(mod):
    got = call(mod, "parse_addresses", FAKE_JSON)
    assert isinstance(got, list), f"parse_addresses() вернула {type(got).__name__}, ждём список пар (имя, адрес/префикс)"
    norm = []
    for item in got:
        assert isinstance(item, (tuple, list)) and len(item) == 2, \
            f"в списке от parse_addresses() элемент {item!r} — ждём пару (имя интерфейса, \"адрес/префикс\")"
        norm.append(tuple(item))
    if norm == FAKE_PAIRS:
        return
    if any(":" in str(x[1]) for x in norm):
        raise AssertionError("в списке от parse_addresses() есть IPv6-адреса (с двоеточиями) — оставь только "
                             "адреса с family == \"inet\"")
    if any(isinstance(x[1], str) and "/" not in x[1] for x in norm):
        raise AssertionError(f"адрес без префикса: {norm[:2]} … — нужна строка \"адрес/префикс\" из local и prefixlen")
    if ("wlx0", "192.168.50.20/24") in norm and ("wlx0", "192.168.50.21/24") not in norm:
        raise AssertionError("у интерфейса wlx0 учебного сервера два IPv4-адреса, а в списке только первый — "
                             "берёшь addr_info[0]? Нужен цикл по всем адресам интерфейса")
    if sorted(norm) == sorted(FAKE_PAIRS):
        raise AssertionError("адреса верные, но порядок не тот — нужен порядок, как в выводе ip -j addr")
    raise AssertionError("parse_addresses(вывод ip -j addr учебного сервера) вернула\n"
                         f"    {norm!r}\n  ждём\n    {FAKE_PAIRS!r}")


def check_step2():
    mod = load()
    check_parse(mod)
    one = json.dumps([FAKE[0]])
    got = call(mod, "parse_addresses", one)
    assert [tuple(x) for x in got] == [("lo", "127.0.0.1/8")], \
        f"parse_addresses() с одним интерфейсом lo вернула {got!r}, ждём [('lo', '127.0.0.1/8')]"
    got = call(mod, "parse_addresses", json.dumps([FAKE[1]]))
    assert list(got) == [], f"интерфейс без адресов (addr_info пустой) → пустой список, а parse_addresses() вернула {got!r}"

    # get_ip_json — с заглушкой ip
    with FakeIp() as fake:
        saved = os.environ.get("PATH", "")
        os.environ["PATH"] = fake.path
        try:
            got = call(mod, "get_ip_json")
        finally:
            os.environ["PATH"] = saved
        calls = fake.log()
    if isinstance(got, bytes):
        raise AssertionError("get_ip_json() вернула bytes, а нужен текст — у subprocess.run есть text=True (урок Python 07)")
    if isinstance(got, subprocess.CompletedProcess):
        raise AssertionError("get_ip_json() вернула весь результат subprocess.run, а нужен текст вывода — .stdout")
    if isinstance(got, (list, dict)):
        raise AssertionError("get_ip_json() вернула уже разобранный JSON — она только запускает ip и возвращает текст, "
                             "разбирает его parse_addresses()")
    assert calls, "get_ip_json() не вызвала ip — заглушка ни разу не запустилась. ip вызывается по имени, без пути?"
    assert isinstance(got, str) and got.strip() in (FAKE_JSON.strip(), FAKE_JSON4.strip()), f"get_ip_json() вернула {show(str(got), 200)!r} — ждём вывод ip -j addr " \
                                           f"(команду вызвали так: ip {calls[-1]})"

    # main() целиком — с заглушкой ip
    with FakeIp() as fake:
        code, out, err = run_script(fake.path)
        calls = fake.log()
    if "Заглушка ip" in err:
        raise AssertionError(f"скрипт вызвал ip не так: ip {calls[-1] if calls else ''} — нужен ip -j addr")
    assert code == 0 and not err, f"python3 addr_report.py (учебный сервер) упал, код {code}: {last_error(err)}"
    lines = out.splitlines()
    want = [f"{n}: {a}" for n, a in FAKE_PAIRS]
    bad = [w for w, l in zip(want, lines) if not (l == w or l.startswith(w + " "))]
    assert len(lines) == len(want) and not bad, \
        "python3 addr_report.py на учебном сервере — ждём строку на адрес:\n    " + "\n    ".join(want) + \
        "\n  сейчас:\n    " + "\n    ".join(lines[:12] or ["(пусто)"])

    # по-настоящему
    real = real_ip_json()
    if real is None:
        print("  ℹ️  настоящего ip на этой машине нет — по-настоящему не запускаю")
    else:
        code, out, err = run_script()
        assert code == 0 and not err, f"python3 addr_report.py на адресах этой машины упал, код {code}: {last_error(err)}"
        pairs = ref_pairs(real)
        lines = out.splitlines()
        want = [f"{n}: {a}" for n, a in pairs]
        bad = [w for w, l in zip(want, lines) if not (l == w or l.startswith(w + " "))]
        assert len(lines) == len(want) and not bad, \
            "на адресах этой машины ждём:\n    " + "\n    ".join(want) + "\n  сейчас:\n    " + "\n    ".join(lines or ["(пусто)"])
        print(f"  ✅ по-настоящему: IPv4-адресов этой машины — {len(pairs)}, строки верные")
    if step and ANSWERS.exists():
        check_leaks()
    print("Шаг 2 ✅ get_ip_json, parse_addresses, строка на каждый IPv4-адрес")


KIND_CASES = [
    ("127.0.0.1/8", "loopback"), ("169.254.10.20/16", "link-local"),
    ("10.20.0.15/24", "private"), ("172.16.0.1/12", "private"), ("172.31.255.254/16", "private"),
    ("192.168.50.20/24", "private"), ("100.64.0.1/10", "shared"), ("100.127.255.254/32", "shared"),
    ("100.101.102.103/32", "shared"), ("203.0.113.10/24", "public"), ("11.0.0.1/8", "public"),
    ("172.15.255.254/16", "public"), ("172.32.0.1/16", "public"), ("100.63.255.254/32", "public"),
    ("100.128.0.1/32", "public"), ("192.169.0.1/16", "public"),
]
NETWORK_CASES = [("10.20.0.15/24", "10.20.0.0/24"), ("192.168.5.77/22", "192.168.4.0/22"),
                 ("172.17.0.1/16", "172.17.0.0/16"), ("127.0.0.1/8", "127.0.0.0/8"),
                 ("100.101.102.103/32", "100.101.102.103/32")]


def check_step3():
    mod = load()
    for address, want in NETWORK_CASES:
        f = func(mod, "get_network")
        try:
            got = f(address)
        except ValueError as e:
            if "host bits" in str(e):
                raise AssertionError(f"get_network({address!r}) упала: ValueError: {e} — ip_network на адресе устройства "
                                     "с префиксом падает. Как получить сеть из такого адреса — 🔎 шага 3")
            raise AssertionError(f"get_network({address!r}) упала: ValueError: {e}")
        except Exception as e:
            raise AssertionError(f"get_network({address!r}) упала: {type(e).__name__}: {e}")
        if not isinstance(got, str) and str(got) == want:
            raise AssertionError(f"get_network({address!r}) вернула объект {got!r}, а нужна строка — str(...)")
        assert got == want, f"get_network({address!r}) вернула {got!r}, ждём {want!r}"
    print("  ✅ get_network: сеть по адресу с префиксом, в том числе /22 и /32")

    got_all = {}
    for address, want in KIND_CASES:
        f = func(mod, "get_kind")
        try:
            got_all[address] = f(address)
        except AttributeError as e:
            if "_version" in str(e):
                raise AssertionError(f"get_kind({address!r}) упала: AttributeError: {e} — в in слева строка. "
                                     "Проверять через in можно объект ip_address(...), а не строку (урок, часть 5)")
            raise AssertionError(f"get_kind({address!r}) упала: AttributeError: {e}")
        except Exception as e:
            raise AssertionError(f"get_kind({address!r}) упала: {type(e).__name__}: {e}")
    wrong = [(a, w, got_all[a]) for a, w in KIND_CASES if got_all[a] != w]
    if wrong:
        g = got_all
        if g["10.20.0.15/24"] == "public" and g["127.0.0.1/8"] == "loopback":
            hint = "Похоже, return \"public\" стоит внутри цикла по таблице: тогда проверяется только первая сеть " \
                   "(как в Задаче 20). public — после цикла"
        elif g["127.0.0.1/8"] == "private" or g["203.0.113.10/24"] == "private":
            hint = "Похоже на is_private — он шире, чем три частные сети (урок, «Потом»). В задаче вид берётся из своей таблицы"
        elif g["172.32.0.1/16"] == "private" or g["100.128.0.1/32"] == "shared" or g["192.169.0.1/16"] == "private":
            hint = "Похоже на сравнение строк (startswith): границы /12 и /10 проходят внутри второго числа. " \
                   "Проверяй ip_address(...) in ip_network(...)"
        else:
            hint = "Сверь таблицу сетей в скрипте с таблицей в условии"
        raise AssertionError("get_kind() ошибается:\n" + "\n".join(
            f"    {a} → {gg!r}, ждём {w!r}" for a, w, gg in wrong[:6]) + f"\n  {hint}")
    print("  ✅ get_kind: все виды и границы — 172.15/172.16, 172.31/172.32, 100.63/100.64, 100.127/100.128")

    for name, address in [("wlx0", "192.168.50.20/24"), ("tailscale0", "100.101.102.103/32"), ("ens19", "203.0.113.10/24")]:
        got = call(mod, "format_line", name, address)
        want = ref_line(name, address)
        assert got == want, f"format_line({name!r}, {address!r}) вернула\n    {got!r}\n  ждём\n    {want!r}"
    print("  ✅ format_line")

    with FakeIp() as fake:
        code, out, err = run_script(fake.path)
    assert code == 0 and not err, f"python3 addr_report.py (учебный сервер) упал, код {code}: {last_error(err)}"
    want = [ref_line(n, a) for n, a in FAKE_PAIRS]
    lines = out.splitlines()
    assert lines == want, "python3 addr_report.py на учебном сервере — ждём:\n    " + "\n    ".join(want) + \
                          "\n  сейчас:\n    " + "\n    ".join(lines[:12] or ["(пусто)"])
    for l in lines:
        assert not CYRILLIC.search(l), f"в выводе русский текст — скрипт печатает по-английски: {l}"
    print("  ✅ python3 addr_report.py на учебном сервере: все 8 строк")

    real = real_ip_json()
    if real is None:
        print("  ℹ️  настоящего ip на этой машине нет — по-настоящему не запускаю")
    else:
        code, out, err = run_script()
        assert code == 0 and not err, f"python3 addr_report.py на адресах этой машины упал, код {code}: {last_error(err)}"
        want = [ref_line(n, a) for n, a in ref_pairs(real)]
        lines = out.splitlines()
        assert lines == want, "на адресах этой машины ждём:\n    " + "\n    ".join(want) + \
                              "\n  сейчас:\n    " + "\n    ".join(lines or ["(пусто)"])
        print(f"  ✅ по-настоящему: строк — {len(want)}, все совпадают")
    if step and ANSWERS.exists():
        check_leaks()
    print("Шаг 3 ✅ сеть и вид каждого адреса")


def check_step4():
    answers()
    for name in (".gitignore", "addr_report.py", "test_addr_report.py"):
        assert in_git(name), f"{name} не добавлен в Git (git add)"
    print("  ✅ .gitignore, addr_report.py и test_addr_report.py в Git")
    check_answers_ignored()
    assert not git("log", "--oneline", "main..HEAD", "--", "answers.txt").stdout.strip(), \
        "answers.txt есть в истории ветки (в одном из коммитов) — напиши мне, уберём"
    print("  ✅ answers.txt нет ни в Git, ни в истории ветки")
    check_leaks()
    assert README.exists() and "`day27/`" in README.read_text(encoding="utf-8"), \
        "в README (корень репозитория) нет строки для `day27/` в таблице Structure"
    print("  ✅ в README есть строка для day27/")
    status = git("status", "--porcelain", "--", ".", str(README)).stdout.strip()
    assert not status, f"git status: есть незакоммиченные изменения — {status}"
    print("  ✅ git status: в папке задачи и README всё закоммичено")
    print("Шаг 4 ✅ Git и README")


steps = {1: check_step1, 2: check_step2, 3: check_step3, 4: check_step4}
if step:
    if step not in steps:
        print(f"Нет шага {step}: шаги 1–4")
        sys.exit(2)
    try:
        steps[step]()
    except AssertionError as e:
        print(f"Шаг {step} ❌ {e}")
        sys.exit(1)
else:
    failed = 0
    for n, f in steps.items():
        try:
            f()
        except AssertionError as e:
            print(f"Шаг {n} ❌ {e}")
            failed += 1
    if failed:
        print(f"\nНе прошло шагов: {failed}")
        sys.exit(1)
    print("\nВсе тесты прошли ✅")
