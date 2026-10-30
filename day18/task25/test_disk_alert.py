# Тесты к Задаче 25. Запуск из папки задачи:
#   python3 test_disk_alert.py      — все шаги
#   python3 test_disk_alert.py 2    — только шаг 2 (номера шагов — из условия задачи)
# Шаги 4–5 запускают disk_alert.py во временной папке с «поддельной» командой df:
# она печатает заранее заготовленный текст. Так результат не зависит от твоих
# настоящих дисков, а твой alerts.json тесты не трогают.
import importlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

here = Path(__file__).parent
step = int(sys.argv[1]) if len(sys.argv) > 1 else 0   # 0 = все шаги

GB = 1024 * 1024   # в одном ГБ 1024 * 1024 блоков по 1 КБ

# Вывод df -P только с настоящими дисками — для шага 2
REAL_ONLY = """Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sdd        1055762868  20000000 982046484       2% /
/dev/sdb1          1000000    950000     50000      95% /data
"""

# Вывод df -P, похожий на WSL, + snap-пакет (/dev/loop0) — для шагов 3–5
FULL = """Filesystem     1024-blocks      Used Available Capacity Mounted on
none               8126440         4   8126436       1% /usr/lib/modules/6.6.87.2-microsoft-standard-WSL2
none               8126440         4   8126436       1% /mnt/wsl
drivers          498780156 410000000  88780156      83% /usr/lib/wsl/drivers
/dev/sdd        1055762868  20000000 982046484       2% /
none               8126440       100   8126340       1% /mnt/wslg
rootfs             8122480      2700   8119780       1% /init
tmpfs              8126440         0   8126440       0% /run
C:\\              498780156 410000000  88780156      83% /mnt/c
/dev/loop0           65536     65536         0     100% /snap/core22/1380
/dev/sdb1          1000000    950000     50000      95% /data
/dev/sdc           2000000   1600000    400000      80% /backup
"""


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


def run(df_text="", df_code=0, env=None):
    """Запускает disk_alert.py во временной папке с поддельной командой df.
    → (код выхода, stdout, stderr, текст alerts.json или None)"""
    script = here / "disk_alert.py"
    assert script.exists(), "нет файла disk_alert.py в папке задачи"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        shutil.copy(script, tmp)
        bindir = tmp / "fakebin"
        bindir.mkdir()
        (bindir / "output.txt").write_text(df_text, encoding="utf-8")
        fake = bindir / "df"
        fake.write_text(
            '#!/bin/sh\n'
            'dir="$(dirname "$0")"\n'
            'touch "$dir/called"\n'
            f'if [ {df_code} -ne 0 ]; then\n'
            '  echo "df: /mnt/broken: Transport endpoint is not connected" >&2\n'
            f'  exit {df_code}\n'
            'fi\n'
            'cat "$dir/output.txt"\n',
            encoding="utf-8")
        fake.chmod(0o755)
        full_env = {k: v for k, v in os.environ.items() if not k.startswith("DISK_")}
        full_env["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
        full_env.update(env or {})
        r = subprocess.run([sys.executable, str(tmp / "disk_alert.py")], cwd=tmp,
                           env=full_env, capture_output=True, text=True, timeout=10)
        called = (bindir / "called").exists()
        alerts_file = tmp / "alerts.json"
        alerts = alerts_file.read_text(encoding="utf-8") if alerts_file.exists() else None
    assert "Traceback" not in r.stderr, \
        "скрипт упал с traceback:\n" + "\n".join("    " + l for l in r.stderr.strip().splitlines()[-3:])
    assert called, "скрипт не запустил команду df. Запускай её просто по имени: [\"df\", \"-P\"]"
    return r.returncode, r.stdout, r.stderr, alerts


def close(a, b):
    return abs(a - b) < 0.01


# ---------- шаги ----------

def check_step1():
    out = call("get_df_output")
    assert isinstance(out, str), \
        f"get_df_output() должна вернуть строку (текст, который напечатал df), а вернула {type(out).__name__}"
    assert "Mounted on" in out, "в том, что вернула get_df_output(), нет заголовка df «Mounted on»"
    assert "1024-blocks" in out, "в заголовке нет «1024-blocks» — df запущен без -P или с -h?"
    print("Шаг 1 ✅ get_df_output() возвращает вывод df -P")


def check_step2():
    disks = call("parse_df", REAL_ONLY)
    assert isinstance(disks, list), f"parse_df() должна вернуть список, а вернула {type(disks).__name__}"
    assert len(disks) == 2, \
        f"в тексте заголовок + 2 диска → ждали список из 2 словарей, получили {len(disks)}: {disks}"
    for d in disks:
        assert isinstance(d, dict), f"элементы списка должны быть словарями, а тут {type(d).__name__}: {d!r}"
        missing = {"name", "used_gb", "total_gb"} - set(d)
        assert not missing, f"в словаре {d} нет ключей: {', '.join(sorted(missing))}"
        for key in ("used_gb", "total_gb"):
            v = d[key]
            assert isinstance(v, (int, float)) and not isinstance(v, bool), \
                f"{key} должен быть числом, а это {type(v).__name__}: {v!r} (из текста всё приходит строками)"
    names = [d["name"] for d in disks]
    assert names == ["/", "/data"], \
        f"name — точка монтирования (последняя колонка). Получили {names}, ждали ['/', '/data']"
    want = [(20000000 / GB, 1055762868 / GB), (950000 / GB, 1000000 / GB)]
    for d, (used, total) in zip(disks, want):
        assert close(d["used_gb"], used) and close(d["total_gb"], total), \
            (f"{d['name']}: used_gb={d['used_gb']}, total_gb={d['total_gb']}, "
             f"ждали примерно {used:.2f} и {total:.2f} — блоки по 1 КБ, в ГБ это / 1024 / 1024")
    print("Шаг 2 ✅ parse_df() разбирает вывод df")


def check_step3():
    cases = {"/dev/sda1": True, "/dev/sdd": True, "/dev/nvme0n1p2": True,
             "/dev/loop0": False, "/dev/loop12": False,
             "tmpfs": False, "none": False, "drivers": False, "rootfs": False, "C:\\": False}
    for fs, want in cases.items():
        got = call("is_real_disk", fs)
        assert got is want, f"is_real_disk({fs!r}) вернула {got!r}, ждали {want}"
    disks = call("parse_df", FULL)
    names = [d["name"] for d in disks] if isinstance(disks, list) else disks
    assert names == ["/", "/data", "/backup"], \
        f"parse_df() на выводе как в WSL: получили {names}, ждали ['/', '/data', '/backup']"
    print("Шаг 3 ✅ только настоящие диски")


def check_step4():
    code, out, err, alerts = run(FULL)
    assert alerts is not None, "alerts.json не создан"
    for name in ("/data", "/backup"):
        assert name in alerts, f"в alerts.json нет диска {name}:\n{alerts}"
    for name in ("/mnt/c", "/snap/core22/1380"):
        assert name not in alerts, f"в alerts.json попал {name} — это не настоящий диск:\n{alerts}"
    assert "Проверено дисков: 3, проблемных: 2" in out, f"в выводе нет «Проверено дисков: 3, проблемных: 2»:\n{out}"
    assert code == 2, f"/data заполнен на 95% (CRITICAL) — код выхода должен быть 2, а он {code}"

    code, out, err, alerts = run(df_code=1)
    assert code == 3, f"df завершился с ошибкой — код выхода должен быть 3, а он {code}"
    assert "ОШИБКА" in err, f"сообщение должно начинаться с «ОШИБКА» и идти в stderr; stderr: {err!r}"
    print("Шаг 4 ✅ скрипт проверяет диски из df, ошибка df → код 3")


def check_step5():
    for env in ({"DISK_WARNING": "abc"}, {"DISK_CRITICAL": "девяносто"}):
        code, out, err, alerts = run(FULL, env=env)
        shown = " ".join(f"{k}={v}" for k, v in env.items())
        assert code == 3, f"{shown}: код выхода должен быть 3, а он {code}"
        assert "ОШИБКА" in err, f"{shown}: в stderr нет «ОШИБКА»; stderr: {err!r}"

    code, out, err, alerts = run(FULL, env={"DISK_CRITICAL": "96"})
    assert code == 1, f"DISK_CRITICAL=96: /data (95%) и /backup (80%) — WARNING, код должен быть 1, а он {code}"
    print("Шаг 5 ✅ неверные пороги → код 3")


def check_step6():
    path = here / "real_run.txt"
    assert path.exists(), "нет файла real_run.txt"
    lines = [l.strip() for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    text = "\n".join(lines)
    m = re.search(r"Проверено дисков: (\d+), проблемных: (\d+)", text)
    assert m, f"в real_run.txt нет строки «Проверено дисков: N, проблемных: M»:\n{text}"
    assert int(m.group(1)) > 0, "в real_run.txt проверено 0 дисков — parse_df() ничего не нашла на твоей машине"
    assert m.group(1) == m.group(2), \
        f"с DISK_WARNING=0 DISK_CRITICAL=100 проблемными должны стать все диски, а тут {m.group(0)}"
    assert lines[-1] == "1", f"последняя строка real_run.txt — код выхода, ждали 1, а там {lines[-1]!r}"
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
