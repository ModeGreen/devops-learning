import os
import sys
import subprocess
from pathlib import Path
from disk_v8 import load_mounts, get_disk_usage, get_thresholds, get_hostname

here = Path(__file__).parent
script = here / "disk_v8.py"


def run(args=None, env_extra=None):
    """Запускает disk_v8.py как отдельную программу, возвращает result от subprocess.run."""
    env = os.environ.copy()
    env.pop("DISK_WARNING", None)
    env.pop("DISK_CRITICAL", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run([sys.executable, str(script)] + (args or []),
                          capture_output=True, text=True, env=env)


# --- load_mounts: нет файла -> FileNotFoundError летит наружу (ловит main, а не load_mounts)
try:
    load_mounts(here / "_no_such_file.txt")
    assert False, "load_mounts должна пропустить FileNotFoundError наружу"
except FileNotFoundError:
    pass

# --- get_disk_usage: как раньше
assert get_disk_usage("/")["capacity"] > 0
assert get_disk_usage("/no/such/mount") is None

# --- get_thresholds: по умолчанию и из окружения
os.environ.pop("DISK_WARNING", None)
os.environ.pop("DISK_CRITICAL", None)
assert get_thresholds() == (75, 90)
os.environ["DISK_WARNING"] = "60"
os.environ["DISK_CRITICAL"] = "80"
assert get_thresholds() == (60, 80)

# --- get_thresholds: не число -> ValueError, в сообщении имя переменной и значение
os.environ["DISK_WARNING"] = "abc"
try:
    get_thresholds()
    assert False, "DISK_WARNING=abc должно вызвать ValueError"
except ValueError as e:
    assert "DISK_WARNING" in str(e), f"в сообщении нет имени переменной: {e}"
    assert "abc" in str(e), f"в сообщении нет плохого значения: {e}"
os.environ["DISK_WARNING"] = "75"

os.environ["DISK_CRITICAL"] = "9o"   # буква o вместо нуля
try:
    get_thresholds()
    assert False, "DISK_CRITICAL=9o должно вызвать ValueError"
except ValueError as e:
    assert "DISK_CRITICAL" in str(e), f"в сообщении нет имени переменной: {e}"

# --- get_thresholds: числа, но бессмысленные -> ValueError
for w, c in [("95", "90"), ("90", "90"), ("0", "90"), ("75", "150")]:
    os.environ["DISK_WARNING"] = w
    os.environ["DISK_CRITICAL"] = c
    try:
        get_thresholds()
        assert False, f"пороги {w}/{c} должны вызвать ValueError"
    except ValueError:
        pass
os.environ.pop("DISK_WARNING")
os.environ.pop("DISK_CRITICAL")

# --- get_hostname: команды hostname нет -> "unknown", без падения
assert get_hostname() not in ("", "unknown")
saved_path = os.environ["PATH"]
os.environ["PATH"] = "/no/such/dir"
try:
    assert get_hostname() == "unknown"
finally:
    os.environ["PATH"] = saved_path

# --- main целиком (запуск как программы)
# нормальный запуск: код 0/1/2, ошибок нет
r = run()
assert r.returncode in (0, 1, 2), f"код {r.returncode}, stderr: {r.stderr}"
assert "Traceback" not in r.stderr

# нет файла с дисками -> код 3, сообщение в stderr, stdout пустой
r = run(["/no/such/mounts.txt"])
assert r.returncode == 3, f"ожидался код 3, получен {r.returncode}"
assert "ОШИБКА" in r.stderr and "Traceback" not in r.stderr, r.stderr
assert r.stdout == "", "ошибки печатаются в stderr, а не в stdout"

# порог не число -> код 3
r = run(env_extra={"DISK_WARNING": "abc"})
assert r.returncode == 3, f"ожидался код 3, получен {r.returncode}"
assert "ОШИБКА" in r.stderr and "DISK_WARNING" in r.stderr, r.stderr
assert r.stdout == ""

# пороги перепутаны -> код 3
r = run(env_extra={"DISK_WARNING": "95", "DISK_CRITICAL": "90"})
assert r.returncode == 3, f"ожидался код 3, получен {r.returncode}"
assert "Traceback" not in r.stderr

# лог нельзя записать -> предупреждение в stderr, отчёт напечатан, код как обычно
if os.geteuid() != 0:          # root игнорирует права, проверка имеет смысл только для обычного пользователя
    log = here / "report.log"
    log.touch()
    log.chmod(0o444)           # только чтение
    try:
        r = run()
        assert r.returncode in (0, 1, 2), f"код {r.returncode}, stderr: {r.stderr}"
        assert "ВНИМАНИЕ" in r.stderr and "Traceback" not in r.stderr, r.stderr
        assert r.stdout != "", "отчёт должен напечататься, даже если лог не записался"
    finally:
        log.chmod(0o644)

print("Все тесты прошли")
