import os
import sys
import subprocess
from pathlib import Path
from log_check import (parse_line, load_requests, count_statuses, get_top_ip,
                       get_error_rate, get_max_error_rate, get_exit_code)

here = Path(__file__).parent
script = here / "log_check.py"


def run(args=None, env_extra=None):
    """Запускает log_check.py как отдельную программу."""
    env = os.environ.copy()
    env.pop("LOG_MAX_ERROR_RATE", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run([sys.executable, str(script)] + (args or []),
                          capture_output=True, text=True, env=env)


def req(ip, status):
    """Короткий способ сделать запрос-словарь для тестов."""
    return {"ip": ip, "method": "GET", "path": "/", "status": status, "size": 0}


# --- parse_line: правильная строка
line = '10.0.0.5 - - [14/Oct/2026:10:00:04 +0700] "POST /api/login HTTP/1.1" 401 64'
assert parse_line(line) == {"ip": "10.0.0.5", "method": "POST", "path": "/api/login",
                            "status": 401, "size": 64}, parse_line(line)

# --- parse_line: битые строки -> ValueError
bad_lines = [
    "это не строка лога",                                                      # мало частей
    '10.0.0.5 - - [14/Oct/2026:10:00:04 +0700] "GET / HTTP/1.1" OK 64',         # статус не число
    '10.0.0.5 - - [14/Oct/2026:10:00:04 +0700] "GET / HTTP/1.1" 200 -',         # размер не число
    '10.0.0.5 - - [14/Oct/2026:10:00:04 +0700] "GET / HTTP/1.1" 200 64 extra',  # лишняя часть
]
for bad in bad_lines:
    try:
        parse_line(bad)
        assert False, f"parse_line должна бросить ValueError на: {bad}"
    except ValueError:
        pass

# --- load_requests: пустые строки пропускаются, битые считаются
tmp = here / "_test_access.log"
tmp.write_text(line + "\n\n" + "мусор\n" + line + "\n", encoding="utf-8")
requests, bad_count = load_requests(tmp)
tmp.unlink()
assert len(requests) == 2, f"ожидалось 2 запроса, получено {len(requests)}"
assert bad_count == 1, f"ожидалась 1 битая строка, получено {bad_count}"

# --- load_requests: нет файла -> FileNotFoundError наружу
try:
    load_requests(here / "_no_such.log")
    assert False, "load_requests должна пропустить FileNotFoundError наружу"
except FileNotFoundError:
    pass

# --- count_statuses
reqs = [req("a", 200), req("b", 200), req("a", 404), req("c", 500)]
assert count_statuses(reqs) == {200: 2, 404: 1, 500: 1}
assert count_statuses([]) == {}

# --- get_top_ip: самый частый IP и сколько раз
assert get_top_ip(reqs) == ("a", 2)
assert get_top_ip([req("x", 200)]) == ("x", 1)

# --- get_error_rate: процент ответов 5xx (500 и выше)
assert get_error_rate(reqs) == 25.0
assert get_error_rate([req("a", 499), req("a", 200)]) == 0.0
assert get_error_rate([req("a", 503), req("a", 599)]) == 100.0
assert get_error_rate([]) == 0.0, "пустой список -> 0.0, а не ZeroDivisionError"

# --- get_max_error_rate
os.environ.pop("LOG_MAX_ERROR_RATE", None)
assert get_max_error_rate() == 5
os.environ["LOG_MAX_ERROR_RATE"] = "20"
assert get_max_error_rate() == 20
for value in ["abc", "-1", "101", ""]:
    os.environ["LOG_MAX_ERROR_RATE"] = value
    try:
        get_max_error_rate()
        assert False, f"LOG_MAX_ERROR_RATE='{value}' должно вызвать ValueError"
    except ValueError as e:
        assert "LOG_MAX_ERROR_RATE" in str(e), f"в сообщении нет имени переменной: {e}"
os.environ.pop("LOG_MAX_ERROR_RATE")

# --- get_exit_code(error_rate, max_rate, bad_count)
assert get_exit_code(10.0, 5, 0) == 2       # ошибок больше порога -> CRITICAL
assert get_exit_code(10.0, 5, 3) == 2       # CRITICAL важнее WARNING
assert get_exit_code(5.0, 5, 0) == 0        # ровно на пороге -> ещё OK
assert get_exit_code(0.0, 5, 1) == 1        # есть битые строки -> WARNING
assert get_exit_code(0.0, 5, 0) == 0

# --- main целиком
r = run()                                    # access.log рядом со скриптом
assert r.returncode == 2, f"на access.log ожидался код 2, получен {r.returncode}; stderr: {r.stderr}"
assert "192.168.1.10" in r.stdout, "в отчёте нет самого активного IP"
assert "16.7" in r.stdout, "в отчёте нет процента ошибок 16.7"

r = run(env_extra={"LOG_MAX_ERROR_RATE": "50"})
assert r.returncode == 1, f"порог 50% -> остаётся битая строка -> код 1, получен {r.returncode}"

r = run(["/no/such/access.log"])
assert r.returncode == 3, f"нет файла -> код 3, получен {r.returncode}"
assert "ОШИБКА" in r.stderr and "Traceback" not in r.stderr, r.stderr
assert r.stdout == ""

r = run(env_extra={"LOG_MAX_ERROR_RATE": "много"})
assert r.returncode == 3, f"плохой порог -> код 3, получен {r.returncode}"
assert "ОШИБКА" in r.stderr and "LOG_MAX_ERROR_RATE" in r.stderr, r.stderr

# запуск из другой папки находит access.log рядом со скриптом
r = subprocess.run([sys.executable, str(script)], capture_output=True, text=True, cwd="/")
assert r.returncode == 2, f"запуск из / должен найти access.log, код {r.returncode}; stderr: {r.stderr}"

print("Все тесты прошли")
