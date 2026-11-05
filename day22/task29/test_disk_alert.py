# Тесты к Задаче 29. Запуск из папки задачи на сервере, с активированным venv:
#   python3 test_disk_alert.py      — все шаги
#   python3 test_disk_alert.py 3    — только шаг 3 (номера шагов — из условия задачи)
# Без активации venv тоже можно: .venv/bin/python test_disk_alert.py 3
# Шаг 2 смотрит на настоящие диски сервера. Шаги 4–5 запускают disk_alert.py во временной
# папке с «поддельной» командой findmnt — твои alerts.json и history.log тесты не трогают.
import importlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

here = Path(__file__).parent
step = int(sys.argv[1]) if len(sys.argv) > 1 else 0   # 0 = все шаги


def fs(source, size, used, target, fstype="ext4"):
    return {"source": source, "fstype": fstype, "size": size, "used": used,
            "avail": size - used, "use%": f"{round(used / size * 100) if size else 0}%", "target": target}


# Вывод findmnt: / — 1.9%, /var — 95%, /home — 80%
FULL = json.dumps({"filesystems": [
    fs("tmpfs", 8321474560, 4096, "/run", "tmpfs"),
    fs("/dev/sda2", 1081101176832, 20480000000, "/"),
    fs("overlay", 510750879744, 419840000000, "/var/lib/docker/overlay2/abc/merged", "overlay"),
    fs("/dev/sdb1", 1024000000, 972800000, "/var"),
    fs("/dev/sdc", 2048000000, 1638400000, "/home"),
]}, indent=3)

# Свои пороги у /var и /home → WARNING только у /var
CONFIG = """\
default:
  warning: 75
  critical: 90
disks:
  /var:
    critical: 97
  /home:
    warning: 85
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

TIME = r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d"


# ---------- вспомогательное ----------

def check_yaml():
    try:
        import yaml  # noqa: F401
    except ImportError:
        raise AssertionError("нет модуля yaml. Активирован venv? source .venv/bin/activate "
                             "(или запускай тест так: .venv/bin/python test_disk_alert.py)")


def real_hostname():
    return subprocess.run(["hostname"], capture_output=True, text=True).stdout.strip()


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


def run(config=CONFIG, env=None, extra=None, output=FULL, fail=False):
    """Запускает disk_alert.py во временной папке с поддельной findmnt.
    config — текст disk_alert.yaml рядом со скриптом (None — файла нет),
    extra — {имя: текст} других файлов во временной папке, fail — findmnt завершается с кодом 1.
    → (код выхода, stdout, stderr, текст history.log рядом со скриптом или None)"""
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
        if fail:
            fake.write_text('#!/bin/sh\necho "findmnt: сломался" >&2\nexit 1\n', encoding="utf-8")
        else:
            fake.write_text('#!/bin/sh\ncat "$(dirname "$0")/output.txt"\n', encoding="utf-8")
        fake.chmod(0o755)
        full_env = {k: v for k, v in os.environ.items() if not k.startswith("DISK_")}
        full_env["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
        env = {k: v.replace("{tmp}", str(tmp)) for k, v in (env or {}).items()}
        full_env.update(env)
        # запускаем НЕ из папки скрипта: history.log должен появиться рядом со скриптом
        r = subprocess.run([sys.executable, str(app / "disk_alert.py")], cwd=tmp,
                           env=full_env, capture_output=True, text=True, timeout=10)
        history_file = app / "history.log"
        history = history_file.read_text(encoding="utf-8") if history_file.exists() else None
        wrong_place = (tmp / "history.log").exists()
    assert "Traceback" not in r.stderr, \
        "скрипт упал с traceback:\n" + "\n".join("    " + l for l in r.stderr.strip().splitlines()[-3:])
    assert not wrong_place, \
        "history.log появился в текущей папке, а не рядом со скриптом. Путь — от папки скрипта (script_dir)"
    return r.returncode, r.stdout, r.stderr, history


def one_line(history, why):
    assert history is not None, f"{why}: history.log рядом со скриптом не появился"
    lines = history.splitlines()
    assert len(lines) == 1, f"{why}: за один запуск в history.log должна добавиться одна строка, а там:\n{history}"
    assert history.endswith("\n"), f"{why}: строка в history.log должна кончаться переводом строки \\n"
    return lines[0]


def is_real(source):
    return source.startswith("/dev/") and not source.startswith("/dev/loop")


def read_answers():
    path = here / "answers.txt"
    assert path.exists(), "нет файла answers.txt в папке задачи"
    answers = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            answers[key.strip()] = value.strip()
    return answers


# ---------- шаги ----------

def check_step1():
    assert sys.prefix != sys.base_prefix, \
        "тест запущен не из venv. Сначала source .venv/bin/activate — в приглашении появится (.venv)"
    check_yaml()
    import yaml
    req = here / "requirements.txt"
    assert req.exists(), "нет requirements.txt в папке задачи — скопируй его из day20/task27"
    m = re.search(r"pyyaml==([\w.]+)", req.read_text(encoding="utf-8"), re.IGNORECASE)
    assert m, "в requirements.txt нет строки PyYAML==<версия>"
    assert yaml.__version__ == m.group(1), \
        (f"в venv PyYAML {yaml.__version__}, а в requirements.txt {m.group(1)}. "
         f"Ставь не pip install pyyaml, а pip install -r requirements.txt")
    print(f"Шаг 1 ✅ venv на сервере, PyYAML {yaml.__version__} — та же версия, что в requirements.txt")


def check_step2():
    check_yaml()
    import yaml
    r = subprocess.run(["findmnt", "-D", "-O", "rw", "-b", "-J"], capture_output=True, text=True)
    assert r.returncode == 0, f"findmnt завершился с кодом {r.returncode}: {r.stderr.strip()}"
    mounts = json.loads(r.stdout)["filesystems"]
    config = yaml.safe_load((here / "disk_alert.yaml").read_text(encoding="utf-8"))
    ignore = config.get("ignore", []) if isinstance(config, dict) else []
    real = [m for m in mounts if is_real(m["source"]) and m["target"] not in ignore]
    skipped = {m["source"] for m in mounts if not is_real(m["source"])}
    root = [m["source"] for m in mounts if m["target"] == "/"]

    answers = read_answers()
    for key in ("checked", "root", "skipped"):
        assert key in answers and answers[key], f"в answers.txt нет строки «{key}: ...» или она пустая"

    assert answers["checked"].isdigit(), f"checked — это число, а в answers.txt {answers['checked']!r}"
    assert int(answers["checked"]) == len(real), \
        (f"checked: {answers['checked']} — а скрипт на этом сервере проверяет {len(real)}. "
         f"Посмотри «Проверено дисков: N» в выводе disk_alert.py")
    assert root, "на этой машине findmnt не показал диск / — тест запущен на сервере?"
    assert answers["root"] == root[0], \
        f"root: {answers['root']} — а у диска / в findmnt source {root[0]!r}. Колонка SOURCE, строка с TARGET /"
    if skipped:
        assert answers["skipped"] in skipped, \
            (f"skipped: {answers['skipped']} — такого source среди пропущенных строк findmnt нет. "
             f"Пропущенные: {', '.join(sorted(skipped))}")
    print("Шаг 2 ✅ answers.txt совпадает с дисками сервера")


def check_step3():
    now = datetime(2026, 11, 5, 14, 0, 3)
    got = call("make_history_line", now, "mindserver", "WARNING", "проверено дисков: 3, проблемных: 1")
    want = "2026-11-05 14:00:03 mindserver WARNING проверено дисков: 3, проблемных: 1"
    assert isinstance(got, str), f"make_history_line() должна вернуть строку, а вернула {type(got).__name__}: {got!r}"
    assert not got.endswith("\n"), "make_history_line() возвращает строку без \\n на конце — \\n добавится при записи"
    assert got == want, f"make_history_line() вернула\n    {got!r}\nа ждали\n    {want!r}"

    now = datetime(2026, 1, 2, 9, 5, 7, 123456)
    got = call("make_history_line", now, "web-01", "OK", "всё хорошо")
    want = "2026-01-02 09:05:07 web-01 OK всё хорошо"
    assert got == want, \
        (f"с другим временем make_history_line() вернула\n    {got!r}\nа ждали\n    {want!r}\n"
         f"Время — через strftime, без долей секунды; дата, имя машины, статус, текст — из аргументов")
    print("Шаг 3 ✅ make_history_line() собирает строку журнала")


def check_step4():
    host = real_hostname()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "h.log"
        call("write_history", path, "OK", "первый")
        call("write_history", path, "CRITICAL", "второй")
        lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    assert len(lines) == 2, \
        (f"после двух вызовов write_history() в файле должно быть 2 строки, а их {len(lines)}. "
         f"Файл открывается на дописывание, а не на перезапись?")
    for line, status, text in zip(lines, ("OK", "CRITICAL"), ("первый", "второй")):
        assert re.fullmatch(rf"{TIME} {re.escape(host)} {status} {text}", line), \
            (f"write_history(path, {status!r}, {text!r}) записала\n    {line!r}\n"
             f"а ждали «<дата> <время> {host} {status} {text}». Имя машины — команда hostname")

    code, out, err, history = run()
    assert "Проверено дисков: 3, проблемных: 1" in out, \
        f"вывод на экран не должен меняться — ждали «Проверено дисков: 3, проблемных: 1», а вывод:\n{out}"
    assert code == 1, f"один WARNING — код выхода должен быть 1, а он {code}"
    line = one_line(history, "запуск с одним WARNING")
    assert re.fullmatch(rf"{TIME} {re.escape(host)} WARNING проверено дисков: 3, проблемных: 1", line), \
        f"в history.log\n    {line!r}\nа ждали «<дата> <время> {host} WARNING проверено дисков: 3, проблемных: 1»"

    ok = FULL.replace("972800000", "100000000").replace("1638400000", "100000000")
    code, out, err, history = run(output=ok)
    line = one_line(history, "запуск без проблемных дисков")
    assert line.endswith(f"{host} OK проверено дисков: 3, проблемных: 0"), \
        f"все диски в норме — ждали в конце строки «{host} OK проверено дисков: 3, проблемных: 0», а там\n    {line!r}"

    ig = subprocess.run(["git", "check-ignore", "-q", str(here / "history.log")], cwd=here)
    assert ig.returncode == 0, "history.log не игнорируется Git — это журнал запусков, ему не место в репозитории"
    print("Шаг 4 ✅ каждый запуск дописывает строку в history.log")


def check_step5():
    host = real_hostname()
    now = datetime(2026, 11, 5, 14, 0, 3)
    got = call("make_history_line", now, "mindserver", "UNKNOWN", 'ОШИБКА: while parsing\n  in "a.yaml", line 3\nexpected')
    assert isinstance(got, str) and "\n" not in got, \
        f"текст из нескольких строк — make_history_line() должна вернуть одну строку, а вернула\n    {got!r}"
    assert " ".join(got.split()) == '2026-11-05 14:00:03 mindserver UNKNOWN ОШИБКА: while parsing in "a.yaml", line 3 expected', \
        f"многострочный текст склеивается в одну строку через пробел, а получилось\n    {got!r}"
    cases = [
        (dict(config=None), "нет disk_alert.yaml", None),
        (dict(env={"DISK_ALERT_CONFIG": "{tmp}/broken.yaml"}, extra={"broken.yaml": BROKEN}), "YAML сломан", None),
        (dict(fail=True), "findmnt завершился с ошибкой", None),
        (dict(config=BAD_VAR), "у /var warning больше critical", "/var"),
    ]
    for kwargs, why, must in cases:
        code, out, err, history = run(**kwargs)
        assert code == 3, f"{why} — код выхода должен быть 3, а он {code}"
        assert "ОШИБКА" in err, f"{why}: в stderr нет «ОШИБКА» — экран менять не надо; stderr: {err!r}"
        line = one_line(history, why)
        assert re.fullmatch(rf"{TIME} {re.escape(host)} UNKNOWN ОШИБКА: .+", line), \
            f"{why}: в history.log\n    {line!r}\nа ждали «<дата> <время> {host} UNKNOWN ОШИБКА: <текст ошибки>»"
        if must:
            assert must in line, f"{why}: в строке журнала нет {must} — непонятно, что чинить:\n    {line!r}"
        flat = lambda t: " ".join(t.split())
        assert flat(line.split(" UNKNOWN ", 1)[1]) == flat(err), \
            (f"{why}: в журнале и в stderr должен быть один и тот же текст.\n"
             f"    журнал: {line.split(' UNKNOWN ', 1)[1]!r}\n    stderr: {err.strip()!r}")
    print("Шаг 5 ✅ ошибки тоже попадают в журнал — со статусом UNKNOWN")


def check_step6():
    host = real_hostname()
    path = here / "real_history.txt"
    assert path.exists(), "нет файла real_history.txt"
    lines = [l for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(lines) >= 2, f"в real_history.txt должно быть хотя бы 2 строки (два запуска), а их {len(lines)}"
    for line in lines:
        assert re.fullmatch(rf"{TIME} \S+ (OK|WARNING|CRITICAL|UNKNOWN) .+", line), \
            f"строка real_history.txt не похожа на строку журнала:\n    {line!r}"
    assert any(f" {host} " in l for l in lines), \
        f"в real_history.txt нет запусков на этой машине ({host}). Тест запущен на сервере?"
    assert any(" UNKNOWN ОШИБКА: " in l for l in lines), "в real_history.txt нет запуска со сломанными настройками (UNKNOWN)"
    assert any(re.search(r" (OK|WARNING|CRITICAL) проверено дисков: \d+", l) for l in lines), \
        "в real_history.txt нет обычного запуска (OK/WARNING/CRITICAL, «проверено дисков: N»)"

    need = ["disk_alert.py", "disk_alert.yaml", "requirements.txt", "answers.txt", "real_history.txt",
            "test_disk_alert.py", ".gitignore"]
    missing = [n for n in need if subprocess.run(["git", "ls-files", "--error-unmatch", n], cwd=here,
                                                 capture_output=True).returncode != 0]
    assert not missing, f"не добавлены в Git: {', '.join(missing)} — сначала git add"

    readme = here.parent.parent / "README.md"
    assert readme.exists(), f"не нашёл README.md в {readme.parent} — папка задачи должна быть day22/task29"
    assert "`day22/`" in readme.read_text(encoding="utf-8"), "в таблице Structure в README нет строки для `day22/`"
    print("Шаг 6 ✅ запуски на сервере, файлы в Git, README")


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
