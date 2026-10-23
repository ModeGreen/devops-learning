# Тесты к Задаче 20. Запуск из папки задачи:
#   python3 test_disk_alert.py      — все проверки
#   python3 test_disk_alert.py 2    — только шаг 2 (номера шагов — из условия задачи)
# disk_alert.py запускается на копии во временной папке —
# твои disks.json и alerts.json тесты не трогают.
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

here = Path(__file__).parent
step = int(sys.argv[1]) if len(sys.argv) > 1 else 0   # 0 = все шаги

DISKS = [
    {"name": "/", "used_gb": 41, "total_gb": 50},          # 82%
    {"name": "/var", "used_gb": 93, "total_gb": 100},      # 93%
    {"name": "/home", "used_gb": 120, "total_gb": 500},    # 24%
    {"name": "/data", "used_gb": 900, "total_gb": 1000},   # 90% — ровно на пороге
    {"name": "/backup", "used_gb": 300, "total_gb": 400},  # 75% — ровно на пороге
]


def run(disks=None, env=None, raw=None):
    """Запускает disk_alert.py в чистой временной папке.
    → (код выхода, stdout, stderr, содержимое alerts.json или None)"""
    script = here / "disk_alert.py"
    assert script.exists(), "нет файла disk_alert.py в папке задачи"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        shutil.copy(script, tmp)
        data_file = tmp / "disks.json"
        if raw is not None:
            data_file.write_text(raw, encoding="utf-8")
        elif disks is not None:
            data_file.write_text(json.dumps(disks), encoding="utf-8")
        full_env = {k: v for k, v in os.environ.items() if not k.startswith("DISK_")}
        full_env.update(env or {})
        r = subprocess.run([sys.executable, str(tmp / "disk_alert.py")], cwd=tmp,
                           env=full_env, capture_output=True, text=True, timeout=10)
        alerts_file = tmp / "alerts.json"
        alerts = json.loads(alerts_file.read_text(encoding="utf-8")) if alerts_file.exists() else None
    assert "Traceback" not in r.stderr, \
        "скрипт упал с traceback:\n" + "\n".join("    " + l for l in r.stderr.strip().splitlines()[-3:])
    return r.returncode, r.stdout, r.stderr, alerts


def names(alerts):
    return [(a["name"], a["status"]) for a in alerts]


def check_step1():
    code, out, err, alerts = run(DISKS)
    want = [("/", "WARNING"), ("/var", "CRITICAL"), ("/data", "CRITICAL"), ("/backup", "WARNING")]
    assert alerts is not None, "alerts.json не создан"
    assert names(alerts) == want, f"в alerts.json:\n  получили: {names(alerts)}\n  ждали:    {want}"
    assert [a["percent"] for a in alerts] == [82.0, 93.0, 90.0, 75.0], \
        f"проценты в alerts.json: {[a['percent'] for a in alerts]}, ждали [82.0, 93.0, 90.0, 75.0]"
    assert "Проверено дисков: 5, проблемных: 4" in out, f"в выводе нет «Проверено дисков: 5, проблемных: 4»:\n{out}"
    assert code == 2, f"есть CRITICAL — код выхода должен быть 2, а он {code}"

    only_warn = [{"name": "/home", "used_gb": 10, "total_gb": 100},
                 {"name": "/srv", "used_gb": 80, "total_gb": 100}]
    code, out, err, alerts = run(only_warn)
    assert names(alerts) == [("/srv", "WARNING")], \
        f"диски /home (10%) и /srv (80%): в alerts.json {names(alerts)}, ждали [('/srv', 'WARNING')]"
    assert code == 1, f"только WARNING — код должен быть 1, а он {code}"

    all_ok = [{"name": "/", "used_gb": 10, "total_gb": 100}]
    code, out, err, alerts = run(all_ok)
    assert alerts == [] and code == 0, f"всё в норме — ждали пустой alerts.json и код 0, получили {alerts} и {code}"
    print("Шаг 1 ✅ проверяются все диски")


def check_step2():
    code, out, err, alerts = run(DISKS, env={"DISK_WARNING": "60", "DISK_CRITICAL": "80"})
    want = [("/", "CRITICAL"), ("/var", "CRITICAL"), ("/data", "CRITICAL"), ("/backup", "WARNING")]
    assert names(alerts) == want, \
        f"DISK_WARNING=60 DISK_CRITICAL=80:\n  получили: {names(alerts)}\n  ждали:    {want}"
    assert code == 2, f"код выхода {code}, ждали 2"

    code, out, err, alerts = run(DISKS, env={"DISK_WARNING": "95", "DISK_CRITICAL": "99"})
    assert alerts == [] and code == 0, \
        f"DISK_WARNING=95 DISK_CRITICAL=99: ждали пустой alerts.json и код 0, получили {names(alerts)} и {code}"

    code, out, err, alerts = run(DISKS, env={"DISK_CRITICAL": "85"})
    want = [("/", "WARNING"), ("/var", "CRITICAL"), ("/data", "CRITICAL"), ("/backup", "WARNING")]
    assert names(alerts) == want, f"только DISK_CRITICAL=85:\n  получили: {names(alerts)}\n  ждали:    {want}"
    print("Шаг 2 ✅ пороги из переменных окружения")


def check_step3():
    code, out, err, alerts = run(raw='[\n  {"name": "/", "used_gb": 41, "total_gb": 50\n]\n')
    assert code == 3, f"сломанный JSON — код выхода должен быть 3, а он {code}"
    assert "ОШИБКА" in err, f"сообщение об ошибке должно начинаться с «ОШИБКА» и идти в stderr; stderr: {err!r}"

    code, out, err, alerts = run()          # файла disks.json нет
    assert code == 3 and "ОШИБКА" in err, f"нет файла — ждали код 3 и «ОШИБКА» в stderr, получили {code}, {err!r}"
    print("Шаг 3 ✅ ошибки → код 3")


def check_step4():
    path = here / "bugs.txt"
    assert path.exists(), "нет файла bugs.txt"
    lines = [l for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(lines) == 3, f"в bugs.txt должно быть 3 непустые строки (по одной на баг), а их {len(lines)}"
    ig = subprocess.run(["git", "check-ignore", "-q", str(here / "alerts.json")], cwd=here)
    assert ig.returncode == 0, "alerts.json не игнорируется Git: нужна строка alerts.json в .gitignore"
    print("Шаг 4 ✅ bugs.txt и .gitignore")


steps = {1: check_step1, 2: check_step2, 3: check_step3, 4: check_step4}
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
