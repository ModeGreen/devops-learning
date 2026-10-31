# Тесты к Задаче 25. Запуск из папки задачи:
#   python3 test_disk_alert.py      — все шаги
#   python3 test_disk_alert.py 2    — только шаг 2 (номера шагов — из условия задачи)
# Шаги 4–5 запускают disk_alert.py во временной папке с «поддельной» командой findmnt:
# она печатает заготовленный JSON. Так результат не зависит от твоих настоящих дисков,
# а твой alerts.json тесты не трогают. Шаги 1 и 6 смотрят на твои настоящие диски.
import importlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

here = Path(__file__).parent
step = int(sys.argv[1]) if len(sys.argv) > 1 else 0   # 0 = все шаги

GB = 1024 ** 3   # байт в одном ГБ


def fs(source, size, used, target, fstype="ext4"):
    return {"source": source, "fstype": fstype, "size": size, "used": used,
            "avail": size - used, "use%": f"{round(used / size * 100) if size else 0}%", "target": target}


# Вывод findmnt -D -O rw -b -J только с настоящими дисками — для шага 2
REAL_ONLY = json.dumps({"filesystems": [
    fs("/dev/sdd", 1081101176832, 20480000000, "/"),
    fs("/dev/sdb1", 1024000000, 972800000, "/var"),
]}, indent=3)

# Вывод, похожий на WSL (диски «только для чтения» findmnt уже убрал сам) — для шагов 3–5
FULL = json.dumps({"filesystems": [
    fs("none", 8321474560, 4096, "/mnt/wsl", "tmpfs"),
    fs("drivers", 510750879744, 419840000000, "/usr/lib/wsl/drivers", "9p"),
    fs("/dev/sdd", 1081101176832, 20480000000, "/"),
    fs("none", 8321474560, 102400, "/mnt/wslg", "tmpfs"),
    fs("tmpfs", 8321474560, 0, "/run", "tmpfs"),
    fs("C:\\", 510750879744, 419840000000, "/mnt/c", "9p"),
    fs("/dev/sdb1", 1024000000, 972800000, "/var"),
    fs("/dev/sdc", 2048000000, 1638400000, "/home"),
]}, indent=3)


def real_readonly_mounts():
    """Точки монтирования «только для чтения» на этой машине (по /proc/mounts)."""
    ro = set()
    for line in Path("/proc/mounts").read_text().splitlines():
        parts = line.split()
        if len(parts) >= 4 and "ro" in parts[3].split(","):
            ro.add(parts[1])
    return ro


# ---------- вспомогательное ----------

def load():
    """Импортирует disk_alert.py из папки задачи (каждый раз свежую версию)."""
    script = here / "disk_alert.py"
    assert script.exists(), "нет файла disk_alert.py в папке задачи"
    if str(here) not in sys.path:
        sys.path.insert(0, str(here))
    try:
        if "disk_alert" in sys.modules:
            return importlib.reload(sys.modules["disk_alert"])
        return importlib.import_module("disk_alert")
    except SyntaxError as e:
        raise AssertionError(f"в disk_alert.py синтаксическая ошибка: строка {e.lineno}: {e.msg}")
    except Exception as e:
        raise AssertionError(f"disk_alert.py не импортируется: {type(e).__name__}: {e}")


def call(name, *args):
    """Вызывает функцию name из disk_alert.py. Если она упала — понятное сообщение."""
    f = getattr(load(), name, None)
    assert callable(f), f"в disk_alert.py нет функции {name}()"
    try:
        return f(*args)
    except Exception as e:
        raise AssertionError(f"{name}() упала: {type(e).__name__}: {e}")


def run(output="", code=0, err="", env=None, real=False):
    """Запускает disk_alert.py во временной папке с поддельной командой findmnt
    (real=True — с настоящей). → (код выхода, stdout, stderr, текст alerts.json или None)"""
    script = here / "disk_alert.py"
    assert script.exists(), "нет файла disk_alert.py в папке задачи"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        shutil.copy(script, tmp)
        bindir = tmp / "fakebin"
        bindir.mkdir()
        (bindir / "output.txt").write_text(output, encoding="utf-8")
        (bindir / "err.txt").write_text(err, encoding="utf-8")
        fake = bindir / "findmnt"
        fake.write_text(
            '#!/bin/sh\n'
            'dir="$(dirname "$0")"\n'
            'touch "$dir/called"\n'
            'cat "$dir/err.txt" >&2\n'
            'cat "$dir/output.txt"\n'
            f'exit {code}\n',
            encoding="utf-8")
        fake.chmod(0o755)
        full_env = {k: v for k, v in os.environ.items() if not k.startswith("DISK_")}
        if not real:
            full_env["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
        full_env.update(env or {})
        r = subprocess.run([sys.executable, str(tmp / "disk_alert.py")], cwd=tmp,
                           env=full_env, capture_output=True, text=True, timeout=10)
        called = (bindir / "called").exists()
        alerts_file = tmp / "alerts.json"
        alerts = alerts_file.read_text(encoding="utf-8") if alerts_file.exists() else None
    assert "Traceback" not in r.stderr, \
        "скрипт упал с traceback:\n" + "\n".join("    " + l for l in r.stderr.strip().splitlines()[-3:])
    assert called or real, "скрипт не запустил команду findmnt. Запускай её просто по имени: [\"findmnt\", ...]"
    return r.returncode, r.stdout, r.stderr, alerts


def close(a, b):
    return abs(a - b) < 0.01


# ---------- шаги ----------

def check_step1():
    out = call("get_findmnt_output")
    assert isinstance(out, str), \
        f"get_findmnt_output() должна вернуть строку (текст, который напечатал findmnt), а вернула {type(out).__name__}"
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        raise AssertionError("то, что вернула get_findmnt_output(), — не JSON. Нет ключа -J?")
    assert isinstance(data, dict) and "filesystems" in data, "в JSON нет списка \"filesystems\""
    items = data["filesystems"]
    assert items, "findmnt не нашёл ни одного диска"
    assert "size" in items[0] and "used" in items[0], "в JSON нет размеров (size, used) — нет ключа -D?"
    assert isinstance(items[0]["size"], int), \
        f"size = {items[0]['size']!r} — это не число байт. Нет ключа -b?"
    targets = [i["target"] for i in items]
    ro = real_readonly_mounts() & set(targets)
    assert not ro, f"в выводе есть диски «только для чтения»: {sorted(ro)}. Нет ключей -O rw?"
    assert "/" in targets, "в выводе нет диска «/»"
    print("Шаг 1 ✅ get_findmnt_output() возвращает JSON от findmnt -D -O rw -b -J")


def check_step2():
    disks = call("parse_findmnt", REAL_ONLY)
    assert isinstance(disks, list), f"parse_findmnt() должна вернуть список, а вернула {type(disks).__name__}"
    assert len(disks) == 2, f"в JSON 2 диска → ждали список из 2 словарей, получили {len(disks)}: {disks}"
    for d in disks:
        assert isinstance(d, dict), f"элементы списка должны быть словарями, а тут {type(d).__name__}: {d!r}"
        missing = {"name", "used_gb", "total_gb"} - set(d)
        assert not missing, f"в словаре {d} нет ключей: {', '.join(sorted(missing))}"
    names = [d["name"] for d in disks]
    assert names == ["/", "/var"], f"name — точка монтирования (\"target\"). Получили {names}, ждали ['/', '/var']"
    want = [(20480000000 / GB, 1081101176832 / GB), (972800000 / GB, 1024000000 / GB)]
    for d, (used, total) in zip(disks, want):
        assert close(d["used_gb"], used) and close(d["total_gb"], total), \
            (f"{d['name']}: used_gb={d['used_gb']}, total_gb={d['total_gb']}, "
             f"ждали примерно {used:.2f} и {total:.2f} — размеры в байтах, в ГБ это / 1024 / 1024 / 1024")
    print("Шаг 2 ✅ parse_findmnt() разбирает JSON")


def check_step3():
    cases = {"/dev/sda1": True, "/dev/sdd": True, "/dev/nvme0n1p2": True,
             "tmpfs": False, "none": False, "drivers": False, "C:\\": False}
    for source, want in cases.items():
        got = call("is_real_disk", source)
        assert got is want, f"is_real_disk({source!r}) вернула {got!r}, ждали {want}"
    disks = call("parse_findmnt", FULL)
    names = [d["name"] for d in disks] if isinstance(disks, list) else disks
    assert names == ["/", "/var", "/home"], \
        f"parse_findmnt() на выводе как в WSL: получили {names}, ждали ['/', '/var', '/home']"
    print("Шаг 3 ✅ только настоящие диски")


def check_step4():
    code, out, err, alerts = run(FULL)
    assert alerts is not None, "alerts.json не создан"
    for name in ("/var", "/home"):
        assert f'"{name}"' in alerts, f"в alerts.json нет диска {name}:\n{alerts}"
    assert "/mnt/c" not in alerts, f"в alerts.json попал /mnt/c — это не настоящий диск:\n{alerts}"
    assert "Проверено дисков: 3, проблемных: 2" in out, f"в выводе нет «Проверено дисков: 3, проблемных: 2»:\n{out}"
    assert code == 2, f"/var заполнен на 95% (CRITICAL) — код выхода должен быть 2, а он {code}"

    cases = [
        ("", "findmnt: can't read /proc/self/mountinfo: Permission denied\n", "с сообщением в stderr"),
        ("", "", "молча, без сообщения"),
        (FULL, "findmnt: /mnt/broken: Transport endpoint is not connected\n",
         "с кодом 1, но успел напечатать JSON (проверяй returncode, а не только вывод)"),
    ]
    for output, err_text, case in cases:
        code, out, err, alerts = run(output, code=1, err=err_text)
        assert code == 3, f"findmnt упал {case} — код выхода должен быть 3, а он {code}"
        assert "ОШИБКА" in err, f"findmnt упал {case}: в stderr должно быть «ОШИБКА»; stderr: {err!r}"
    print("Шаг 4 ✅ скрипт проверяет диски из findmnt, ошибка findmnt → код 3")


def check_step5():
    for env in ({"DISK_WARNING": "abc"}, {"DISK_CRITICAL": "девяносто"}):
        code, out, err, alerts = run(FULL, env=env)
        shown = " ".join(f"{k}={v}" for k, v in env.items())
        assert code == 3, f"{shown}: код выхода должен быть 3, а он {code}"
        assert "ОШИБКА" in err, f"{shown}: в stderr нет «ОШИБКА»; stderr: {err!r}"

    code, out, err, alerts = run(FULL, env={"DISK_CRITICAL": "96"})
    assert code == 1, f"DISK_CRITICAL=96: /var (95%) и /home (80%) — WARNING, код должен быть 1, а он {code}"
    print("Шаг 5 ✅ неверные пороги → код 3")


def check_step6():
    path = here / "real_run.txt"
    assert path.exists(), "нет файла real_run.txt"
    lines = [l.strip() for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    text = "\n".join(lines)
    m = re.search(r"Проверено дисков: (\d+), проблемных: (\d+)", text)
    assert m, f"в real_run.txt нет строки «Проверено дисков: N, проблемных: M»:\n{text}"
    assert int(m.group(1)) > 0, "в real_run.txt проверено 0 дисков"
    assert m.group(1) == m.group(2), \
        f"с DISK_WARNING=0 DISK_CRITICAL=100 проблемными должны стать все диски, а тут {m.group(0)}"
    assert lines[-1] == "1", f"последняя строка real_run.txt — код выхода, ждали 1, а там {lines[-1]!r}"
    for mount in real_readonly_mounts():
        assert f"{mount}:" not in text, f"в real_run.txt попал {mount} — он подключён только для чтения"
    ig = subprocess.run(["git", "check-ignore", "-q", str(here / "alerts.json")], cwd=here)
    assert ig.returncode == 0, "alerts.json не игнорируется Git: нужна строка alerts.json в .gitignore"
    print("Шаг 6 ✅ проверка на настоящих дисках")


steps = {1: check_step1, 2: check_step2, 3: check_step3, 4: check_step4, 5: check_step5, 6: check_step6}
if step:
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
    print("Все тесты прошли")
