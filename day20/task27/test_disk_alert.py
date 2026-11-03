# Тесты к Задаче 27. Запуск из папки задачи, с активированным venv:
#   python3 test_disk_alert.py      — все шаги
#   python3 test_disk_alert.py 2    — только шаг 2 (номера шагов — из условия задачи)
# Шаги 3–6 запускают disk_alert.py во временной папке с «поддельной» командой findmnt
# и своим файлом настроек. Так результат не зависит от твоих дисков и твоего disk_alert.yaml,
# а твой alerts.json тесты не трогают. Шаг 7 смотрит на твои настоящие файлы.
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


def fs(source, size, used, target, fstype="ext4"):
    return {"source": source, "fstype": fstype, "size": size, "used": used,
            "avail": size - used, "use%": f"{round(used / size * 100) if size else 0}%", "target": target}


# Вывод findmnt как в WSL: / — 1.9%, /var — 95%, /home — 80%
FULL = json.dumps({"filesystems": [
    fs("none", 8321474560, 4096, "/mnt/wsl", "tmpfs"),
    fs("/dev/sdd", 1081101176832, 20480000000, "/"),
    fs("C:\\", 510750879744, 419840000000, "/mnt/c", "9p"),
    fs("/dev/sdb1", 1024000000, 972800000, "/var"),
    fs("/dev/sdc", 2048000000, 1638400000, "/home"),
]}, indent=3)

# Что должно получиться из твоего disk_alert.yaml (шаг 1)
EXPECTED = {
    "default": {"warning": 75, "critical": 90},
    "disks": {"/var": {"warning": 70, "critical": 85}, "/boot": {"critical": 95}},
    "ignore": ["/mnt/backup"],
}

# Свои пороги у /var и /home → WARNING только у /var
CONFIG_A = """\
default:
  warning: 75
  critical: 90
disks:
  /var:
    critical: 97
  /home:
    warning: 85
"""

# /var не проверяем → WARNING только у /home
CONFIG_B = """\
default:
  warning: 75
  critical: 90
ignore:
  - /var
"""

BROKEN = """\
default:
  warning: 75
  critical: [90
"""

BAD_VAR = """\
default:
  warning: 75
  critical: 90
disks:
  /var:
    warning: 95
    critical: 85
"""


# ---------- вспомогательное ----------

def check_yaml():
    try:
        import yaml  # noqa: F401
    except ImportError:
        raise AssertionError("нет модуля yaml. Активирован venv? source .venv/bin/activate, потом pip install pyyaml")


def load():
    """Импортирует disk_alert.py из папки задачи (каждый раз свежую версию)."""
    check_yaml()
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


def raises_value_error(name, *args):
    """True, если функция бросила ValueError."""
    f = getattr(load(), name, None)
    assert callable(f), f"в disk_alert.py нет функции {name}()"
    try:
        f(*args)
    except ValueError:
        return True
    except Exception as e:
        raise AssertionError(f"{name}() бросила {type(e).__name__}: {e}, а нужно ValueError")
    return False


def run(config=CONFIG_A, env=None, extra=None, output=FULL):
    """Запускает disk_alert.py во временной папке с поддельной findmnt.
    config — текст disk_alert.yaml рядом со скриптом (None — файла нет),
    extra — {имя: текст} других файлов во временной папке.
    → (код выхода, stdout, stderr, текст alerts.json или None, временная папка уже удалена)"""
    check_yaml()
    script = here / "disk_alert.py"
    assert script.exists(), "нет файла disk_alert.py в папке задачи"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        app = tmp / "app"
        app.mkdir()
        shutil.copy(script, app)
        if config is not None:
            (app / "disk_alert.yaml").write_text(config, encoding="utf-8")
        for name, text in (extra or {}).items():
            (tmp / name).write_text(text, encoding="utf-8")
        bindir = tmp / "fakebin"
        bindir.mkdir()
        (bindir / "output.txt").write_text(output, encoding="utf-8")
        fake = bindir / "findmnt"
        fake.write_text('#!/bin/sh\ncat "$(dirname "$0")/output.txt"\n', encoding="utf-8")
        fake.chmod(0o755)
        full_env = {k: v for k, v in os.environ.items() if not k.startswith("DISK_")}
        full_env["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
        env = {k: v.replace("{tmp}", str(tmp)) for k, v in (env or {}).items()}
        full_env.update(env)
        # запускаем НЕ из папки скрипта: файл настроек должен искаться рядом со скриптом
        r = subprocess.run([sys.executable, str(app / "disk_alert.py")], cwd=tmp,
                           env=full_env, capture_output=True, text=True, timeout=10)
        alerts_file = app / "alerts.json"
        alerts = alerts_file.read_text(encoding="utf-8") if alerts_file.exists() else None
    assert "Traceback" not in r.stderr, \
        "скрипт упал с traceback:\n" + "\n".join("    " + l for l in r.stderr.strip().splitlines()[-3:])
    return r.returncode, r.stdout, r.stderr, alerts


# ---------- шаги ----------

def check_step1():
    path = here / "disk_alert.yaml"
    assert path.exists(), "нет файла disk_alert.yaml в папке задачи"
    config = call("load_config", path)
    assert isinstance(config, dict), \
        f"load_config() должна вернуть словарь, а вернула {type(config).__name__}: {config!r}"
    for key in EXPECTED:
        assert key in config, f"в disk_alert.yaml нет секции {key}"
        assert config[key] == EXPECTED[key], \
            f"секция {key}: получили {config[key]!r}, ждали {EXPECTED[key]!r}. Отступы и двоеточия на месте?"
    assert config == EXPECTED, f"в disk_alert.yaml лишнее: {sorted(set(config) - set(EXPECTED))}"
    with tempfile.TemporaryDirectory() as tmp:
        other = Path(tmp) / "other.yaml"
        other.write_text(CONFIG_B, encoding="utf-8")
        got = call("load_config", other)
    assert got == {"default": {"warning": 75, "critical": 90}, "ignore": ["/var"]}, \
        "load_config(path) должна читать файл, который ей передали, а не всегда disk_alert.yaml"
    print("Шаг 1 ✅ load_config() читает disk_alert.yaml")


def check_step2():
    cases = [("/", (75, 90), "диска нет в disks → оба порога из default"),
             ("/var", (70, 85), "у /var свои оба порога"),
             ("/boot", (75, 95), "у /boot свой только critical → warning из default")]
    for name, want, why in cases:
        got = call("get_disk_thresholds", name, EXPECTED)
        assert isinstance(got, tuple) and len(got) == 2, \
            f"get_disk_thresholds() должна вернуть пару (warning, critical), а вернула {got!r}"
        assert got == want, f"get_disk_thresholds({name!r}, ...) вернула {got}, ждали {want}: {why}"
    no_disks = {"default": {"warning": 80, "critical": 95}}
    got = call("get_disk_thresholds", "/", no_disks)
    assert got == (80, 95), \
        f"в настройках нет секции disks — должны работать пороги из default (80, 95), а получили {got}"
    print("Шаг 2 ✅ get_disk_thresholds() — свои пороги диска или default")


def check_step3():
    code, out, err, alerts = run(CONFIG_A)
    hint = ("\nТест запускает скрипт из другой папки: путь к disk_alert.yaml — от папки скрипта (script_dir), "
            "а не просто имя файла") if code == 3 else ""
    assert "Проверено дисков: 3, проблемных: 1" in out, \
        (f"с порогами из файла настроек рядом со скриптом ждали «Проверено дисков: 3, проблемных: 1».\n"
         f"Код {code}, вывод: {out.strip()!r}, stderr: {err.strip()!r}{hint}")
    assert alerts is not None, "alerts.json не создан"
    assert '"/var"' in alerts and '"WARNING"' in alerts, \
        f"/var (95%, свой critical 97) должен быть WARNING:\n{alerts}"
    assert '"/home"' not in alerts, f"/home (80%, свой warning 85) должен быть OK:\n{alerts}"
    assert code == 1, f"один WARNING — код выхода должен быть 1, а он {code}"

    code, out, err, alerts = run(CONFIG_A, env={"DISK_WARNING": "1", "DISK_CRITICAL": "2"})
    assert code == 1, \
        f"скрипт всё ещё берёт пороги из DISK_WARNING/DISK_CRITICAL (код {code}). Теперь пороги только в disk_alert.yaml"
    print("Шаг 3 ✅ main() берёт пороги из disk_alert.yaml")


def check_step4():
    disks = [{"name": "/", "used_gb": 1, "total_gb": 10},
             {"name": "/var", "used_gb": 9, "total_gb": 10},
             {"name": "/home", "used_gb": 8, "total_gb": 10}]
    got = call("remove_ignored", disks, {"default": {}, "ignore": ["/var"]})
    names = [d["name"] for d in got] if isinstance(got, list) else got
    assert names == ["/", "/home"], f"remove_ignored(..., ignore: [/var]) вернула {names}, ждали ['/', '/home']"
    got = call("remove_ignored", disks, {"default": {}})
    names = [d["name"] for d in got] if isinstance(got, list) else got
    assert names == ["/", "/var", "/home"], \
        f"в настройках нет секции ignore — диски должны остаться все, а получили {names}"

    code, out, err, alerts = run(CONFIG_B)
    assert "Проверено дисков: 2, проблемных: 1" in out, \
        f"/var в ignore: ждали «Проверено дисков: 2, проблемных: 1» (пропущенный диск не считается проверенным), а вывод:\n{out}"
    assert '"/var"' not in (alerts or ""), f"/var в ignore, а попал в alerts.json:\n{alerts}"
    assert code == 1, f"/home (80%) — WARNING, код должен быть 1, а он {code}"
    print("Шаг 4 ✅ диски из ignore не проверяются")


def check_step5():
    code, out, err, alerts = run(CONFIG_A, env={"DISK_ALERT_CONFIG": "{tmp}/other.yaml"},
                                 extra={"other.yaml": CONFIG_B})
    assert "Проверено дисков: 2" in out, \
        f"DISK_ALERT_CONFIG указывает на другой файл (в нём /var в ignore), а скрипт его не взял. Вывод:\n{out}"

    code, out, err, alerts = run(None)
    assert code == 3 and "ОШИБКА" in err, \
        f"нет disk_alert.yaml — должно быть ОШИБКА в stderr и код 3; код {code}, stderr: {err!r}"

    cases = [({"DISK_ALERT_CONFIG": "{tmp}/nope.yaml"}, None, "файла настроек нет"),
             ({"DISK_ALERT_CONFIG": "{tmp}/broken.yaml"}, {"broken.yaml": BROKEN}, "YAML сломан")]
    for env, extra, why in cases:
        code, out, err, alerts = run(CONFIG_A, env=env, extra=extra)
        assert code == 3, f"{why} — код выхода должен быть 3, а он {code}"
        assert "ОШИБКА" in err, f"{why}: в stderr нет «ОШИБКА»; stderr: {err!r}"
    print("Шаг 5 ✅ DISK_ALERT_CONFIG, ошибки файла настроек → код 3")


def check_step6():
    good = {"default": {"warning": 75, "critical": 90}}
    cases = [
        ({"default": {"warning": "80%", "critical": 90}}, "/", "warning: 80% — это строка, а не число"),
        ({"default": {"warning": 75, "critical": 90}, "disks": {"/var": {"critical": 9.5}}}, "/var",
         "critical: 9.5 — не целое число"),
        ({"default": {"warning": 75, "critical": 90}, "disks": {"/var": {"warning": 95, "critical": 85}}}, "/var",
         "warning 95 больше critical 85"),
        ({"default": {"warning": 75, "critical": 90}, "disks": {"/var": {"warning": 90}}}, "/var",
         "warning 90 равен critical 90 (critical из default)"),
    ]
    for config, name, why in cases:
        assert raises_value_error("get_disk_thresholds", name, config), \
            f"get_disk_thresholds({name!r}, ...): {why} — нужно бросить ValueError"
    assert call("get_disk_thresholds", "/", good) == (75, 90), "на верных порогах get_disk_thresholds() сломалась"

    code, out, err, alerts = run(BAD_VAR)
    assert code == 3, f"у /var warning 95 > critical 85 — код выхода должен быть 3, а он {code}"
    assert "ОШИБКА" in err and "/var" in err, \
        f"в stderr должно быть «ОШИБКА» и имя диска /var — иначе непонятно, что чинить; stderr: {err!r}"
    print("Шаг 6 ✅ неверные пороги в файле → ValueError → код 3")


def check_step7():
    path = here / "real_run.txt"
    assert path.exists(), "нет файла real_run.txt"
    lines = [l.strip() for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    text = "\n".join(lines)
    m = re.search(r"Проверено дисков: (\d+), проблемных: (\d+)", text)
    assert m, f"в real_run.txt нет строки «Проверено дисков: N, проблемных: M»:\n{text}"
    assert int(m.group(1)) > 0, "в real_run.txt проверено 0 дисков"
    assert m.group(1) == m.group(2), \
        f"с порогами 0 и 100 в real.yaml проблемными должны стать все диски, а тут {m.group(0)}"
    assert lines[-1] == "1", f"последняя строка real_run.txt — код выхода, ждали 1, а там {lines[-1]!r}"

    ig = subprocess.run(["git", "check-ignore", "-q", str(here / "alerts.json")], cwd=here)
    assert ig.returncode == 0, "alerts.json не игнорируется Git: нужна строка alerts.json в .gitignore"
    req = here / "requirements.txt"
    assert req.exists() and "pyyaml" in req.read_text(encoding="utf-8").lower(), \
        "нет requirements.txt с PyYAML: pip freeze > requirements.txt"

    readme = here.parent.parent / "README.md"
    assert readme.exists(), f"не нашёл README.md в {readme.parent} — папка задачи должна быть day20/task27"
    text = readme.read_text(encoding="utf-8")
    missing = [d for d in ("day16/", "day18/", "day19/", "day20/") if f"`{d}`" not in text]
    assert not missing, f"в таблице Structure в README нет строк для: {', '.join(missing)}"
    print("Шаг 7 ✅ запуск на настоящих дисках, requirements.txt, README")


steps = {1: check_step1, 2: check_step2, 3: check_step3, 4: check_step4,
         5: check_step5, 6: check_step6, 7: check_step7}
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
