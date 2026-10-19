# Тесты к Задаче 14. Запуск (venv должен быть активирован!):
#   python test_check_config.py
import sys
import subprocess
import tempfile
from pathlib import Path

here = Path(__file__).parent

# --- окружение: тесты должны идти внутри venv
assert sys.prefix != sys.base_prefix, (
    "тесты запущены НЕ из виртуального окружения. Сначала: source .venv/bin/activate")

req = here / "requirements.txt"
assert req.exists(), "нет requirements.txt (pip freeze > requirements.txt)"
req_lines = [l.strip().lower() for l in req.read_text(encoding="utf-8").splitlines()]
assert any(l.startswith("pyyaml==") for l in req_lines), \
    f"в requirements.txt нет строки PyYAML==<версия>: {req_lines}"

# .venv должен игнорироваться Git — неважно, каким .gitignore (в корне репо или в папке задачи)
ig = subprocess.run(["git", "check-ignore", "-q", str(here / ".venv")], cwd=here)
assert ig.returncode != 128, "папка задачи не внутри Git-репозитория"
assert ig.returncode == 0, ".venv не игнорируется Git: добавь строку .venv/ в .gitignore (в корне репо или здесь)"

from check_config import load_config, check_config, get_exit_code   # noqa: E402

script = here / "check_config.py"


def run(*args):
    """Запускает check_config.py как отдельную программу."""
    return subprocess.run([sys.executable, str(script), *args],
                          capture_output=True, text=True)


def cfg(port=8080, debug=False, drop=None):
    """Собирает словарь-конфиг для тестов; drop — какую секцию убрать."""
    data = {
        "service": {"name": "orders-api", "debug": debug},
        "database": {"host": "db.internal", "port": 5432},
        "server": {"host": "0.0.0.0", "port": port},
    }
    if drop:
        del data[drop]
    return data


# --- check_config: всё хорошо
assert check_config(cfg()) == [], check_config(cfg())

# --- debug
assert check_config(cfg(debug=True)) == ["WARNING: включён debug"], check_config(cfg(debug=True))

# --- нет секций
assert check_config(cfg(drop="database")) == ["CRITICAL: нет секции database"], \
    check_config(cfg(drop="database"))
empty_problems = check_config({})
assert empty_problems == ["CRITICAL: нет секции service", "CRITICAL: нет секции database",
                          "CRITICAL: нет секции server"], empty_problems

# --- порт: границы
for good_port in (1, 80, 65535):
    assert check_config(cfg(port=good_port)) == [], f"порт {good_port} — правильный"
for bad_port in (0, -1, 65536):
    assert check_config(cfg(port=bad_port)) == [f"CRITICAL: неверный порт {bad_port}"], \
        f"порт {bad_port}: {check_config(cfg(port=bad_port))}"

# --- порт: не число
assert check_config(cfg(port="8080")) == ["CRITICAL: неверный порт 8080"], \
    f'порт-строка "8080" (в YAML: port: "8080"): {check_config(cfg(port="8080"))}'
no_port = cfg()
del no_port["server"]["port"]
assert check_config(no_port) == ["CRITICAL: неверный порт None"], \
    f"порта нет вообще: {check_config(no_port)}"
assert check_config(cfg(port=True)) == ["CRITICAL: неверный порт True"], \
    f"порт True (в YAML: port: true): {check_config(cfg(port=True))}"

# --- несколько проблем сразу
both = check_config(cfg(port=0, debug=True))
assert both == ["CRITICAL: неверный порт 0", "WARNING: включён debug"], both

# --- get_exit_code
assert get_exit_code([]) == 0
assert get_exit_code(["WARNING: включён debug"]) == 1
assert get_exit_code(["WARNING: включён debug", "CRITICAL: неверный порт 0"]) == 2
assert get_exit_code(["CRITICAL: нет секции server"]) == 2

# --- main целиком на файлах
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    good = d / "good.yaml"
    good.write_text("service:\n  name: x\n  debug: false\ndatabase:\n  host: db\n"
                    "server:\n  port: 8080\n", encoding="utf-8")
    r = run(str(good))
    assert r.returncode == 0, f"хороший конфиг -> 0, получен {r.returncode}; stderr: {r.stderr}"
    assert r.stdout.strip() == "OK: конфиг в порядке", r.stdout

    # load_config возвращает словарь
    assert load_config(good) == {"service": {"name": "x", "debug": False},
                                 "database": {"host": "db"}, "server": {"port": 8080}}

    debug = d / "debug.yaml"
    debug.write_text("service:\n  debug: true\ndatabase: {}\nserver:\n  port: 80\n", encoding="utf-8")
    r = run(str(debug))
    assert r.returncode == 1, f"debug: true -> 1, получен {r.returncode}"
    assert r.stdout.strip() == "WARNING: включён debug", r.stdout

    bad = d / "bad.yaml"
    bad.write_text("server:\n  port: [8080\n", encoding="utf-8")
    r = run(str(bad))
    assert r.returncode == 3, f"сломанный YAML -> 3, получен {r.returncode}"
    assert "ОШИБКА" in r.stderr and "Traceback" not in r.stderr, r.stderr
    assert r.stdout == "", "при ошибке stdout должен быть пустым"

    empty = d / "empty.yaml"
    empty.write_text("", encoding="utf-8")
    r = run(str(empty))
    assert r.returncode == 3, f"пустой файл -> 3, получен {r.returncode}; stderr: {r.stderr}"
    assert "ОШИБКА" in r.stderr and "Traceback" not in r.stderr, r.stderr

    lst = d / "list.yaml"
    lst.write_text("- a\n- b\n", encoding="utf-8")
    r = run(str(lst))
    assert r.returncode == 3, f"YAML-список вместо словаря -> 3, получен {r.returncode}; stderr: {r.stderr}"

r = run("/no/such/config.yaml")
assert r.returncode == 3, f"нет файла -> 3, получен {r.returncode}"
assert "ОШИБКА" in r.stderr and "Traceback" not in r.stderr, r.stderr

r = run()
assert r.returncode == 3, f"без аргумента -> 3, получен {r.returncode}"
assert "ОШИБКА" in r.stderr and "Traceback" not in r.stderr, r.stderr

# --- конфиг из Задачи 13 (если лежит рядом: ../task13/config.yaml)
t13 = here.parent / "task13" / "config.yaml"
if t13.exists():
    r = run(str(t13))
    assert r.returncode == 0, f"исправленный конфиг Задачи 13 -> 0, получен {r.returncode}: {r.stdout}{r.stderr}"
    print("Конфиг Задачи 13 проверен: OK")

print("Все тесты прошли")
