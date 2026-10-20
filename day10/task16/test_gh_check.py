# Тесты к Задаче 16. Запуск (venv должен быть активирован!):
#   python test_gh_check.py      — все проверки
#   python test_gh_check.py 3    — только шаг 3 (номера шагов — из условия задачи)
# Интернет тестам не нужен: ответы GitHub подменяются заготовками.
import io
import json
import subprocess
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

here = Path(__file__).parent
step = int(sys.argv[1]) if len(sys.argv) > 1 else 0   # 0 = все шаги


def check_step1():
    assert sys.prefix != sys.base_prefix, (
        "тесты запущены НЕ из виртуального окружения. Сначала: source .venv/bin/activate")
    req = here / "requirements.txt"
    assert req.exists(), "нет requirements.txt (pip freeze > requirements.txt)"
    lines = [l.strip().lower() for l in req.read_text(encoding="utf-8").splitlines()]
    assert any(l.startswith("requests==") for l in lines), \
        f"в requirements.txt нет строки requests==<версия>: {lines}"
    ig = subprocess.run(["git", "check-ignore", "-q", str(here / ".venv")], cwd=here)
    assert ig.returncode != 128, "папка задачи не внутри Git-репозитория"
    assert ig.returncode == 0, ".venv не игнорируется Git: нужна строка .venv/ в .gitignore"
    print("Шаг 1 ✅ окружение")


def check_step2():
    path = here / "repo.json"
    assert path.exists(), "нет файла repo.json — запусти explore.py"
    text = path.read_text(encoding="utf-8")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        raise AssertionError(f"repo.json — не JSON: {e}")
    assert isinstance(data, dict), f"в repo.json должен быть объект {{...}}, а там {type(data).__name__}"
    assert data.get("full_name") == "ModeGreen/devops-learning", \
        f'full_name в repo.json: {data.get("full_name")!r}, ждали "ModeGreen/devops-learning"'
    assert '\n  "' in text, "repo.json записан в одну строку — нужен indent=2"
    print("Шаг 2 ✅ repo.json")


SAMPLE = {"full_name": "ModeGreen/devops-learning", "stargazers_count": 3,
          "open_issues_count": 1, "pushed_at": "2026-10-19T10:55:19Z", "language": "Python"}
EXPECTED = "ModeGreen/devops-learning: звёзд 3, открытых issues 1, последний push 2026-10-19T10:55:19Z"


def check_step3():
    from gh_check import make_report
    got = make_report(SAMPLE)
    assert got == EXPECTED, f"make_report:\n  получили: {got!r}\n  ждали:    {EXPECTED!r}"
    other = {"full_name": "a/b", "stargazers_count": 0, "open_issues_count": 0,
             "pushed_at": "2020-01-01T00:00:00Z"}
    got = make_report(other)
    want = "a/b: звёзд 0, открытых issues 0, последний push 2020-01-01T00:00:00Z"
    assert got == want, f"make_report берёт значения из словаря, а не пишет их руками:\n  получили: {got!r}\n  ждали:    {want!r}"
    # на настоящем ответе GitHub
    real = here / "repo.json"
    if real.exists():
        data = json.loads(real.read_text(encoding="utf-8"))
        assert make_report(data).startswith("ModeGreen/devops-learning: звёзд "), make_report(data)
    print("Шаг 3 ✅ make_report")


class FakeResponse:
    """Подделка ответа requests: код + данные."""
    def __init__(self, code, data=None):
        self.status_code = code
        self._data = data

    def json(self):
        return self._data

    def raise_for_status(self):
        import requests
        if self.status_code >= 400:
            raise requests.exceptions.HTTPError(f"{self.status_code} Server Error")


def fake_get(response=None, error=None):
    """Подменяет requests.get внутри gh_check: вернёт response или бросит error."""
    m = mock.Mock()
    if error:
        m.side_effect = error
    else:
        m.return_value = response
    return mock.patch("gh_check.requests.get", m)


def check_step4():
    import requests
    from gh_check import fetch_repo

    with fake_get(FakeResponse(200, SAMPLE)) as m:
        got = fetch_repo("ModeGreen/devops-learning")
    assert got == SAMPLE, f"fetch_repo при коде 200 должна вернуть r.json(), а вернула {got!r}"
    assert m.call_count == 1, f"requests.get вызван {m.call_count} раз, нужен 1"
    args, kwargs = m.call_args
    url = args[0] if args else kwargs.get("url")
    assert url == "https://api.github.com/repos/ModeGreen/devops-learning", f"не тот адрес: {url!r}"
    assert kwargs.get("timeout"), "requests.get вызван без timeout=..."

    with fake_get(FakeResponse(200, {"full_name": "x/y"})) as m:
        fetch_repo("x/y")
    args, kwargs = m.call_args
    url = args[0] if args else kwargs.get("url")
    assert url == "https://api.github.com/repos/x/y", f"адрес должен собираться из аргумента: {url!r}"

    with fake_get(FakeResponse(404, {"message": "Not Found"})):
        got = fetch_repo("ModeGreen/nope")
    assert got is None, f"при коде 404 fetch_repo должна вернуть None, а вернула {got!r}"

    with fake_get(FakeResponse(500, {"message": "oops"})):
        try:
            fetch_repo("ModeGreen/devops-learning")
        except requests.exceptions.HTTPError:
            pass
        else:
            raise AssertionError("при коде 500 fetch_repo должна бросить HTTPError (raise_for_status)")

    with fake_get(error=requests.exceptions.ConnectionError("нет сети")):
        try:
            fetch_repo("ModeGreen/devops-learning")
        except requests.exceptions.ConnectionError:
            pass
        else:
            raise AssertionError("fetch_repo не должна сама ловить ошибки сети — это работа main()")
    print("Шаг 4 ✅ fetch_repo")


def call_main(argv, response=None, error=None):
    """Вызывает main() с подменёнными sys.argv и requests.get. → (код, stdout, stderr)"""
    from gh_check import main
    out, err = io.StringIO(), io.StringIO()
    with fake_get(response, error), mock.patch.object(sys, "argv", ["gh_check.py", *argv]), \
            redirect_stdout(out), redirect_stderr(err):
        code = main()
    return code, out.getvalue(), err.getvalue()


def check_step5():
    import requests
    from gh_check import make_report

    code, out, err = call_main([], FakeResponse(200, SAMPLE))
    assert code == 3, f"без аргумента main() должна вернуть 3, вернула {code!r}"
    assert "ОШИБКА" in err, f"без аргумента — сообщение «ОШИБКА: ...» в stderr. stderr: {err!r}"

    code, out, err = call_main(["ModeGreen/devops-learning"], FakeResponse(200, SAMPLE))
    assert code == 0, f"репозиторий найден → код 0, а вернулось {code!r} (stderr: {err!r})"
    assert out.strip() == make_report(SAMPLE), f"в stdout должен быть отчёт make_report. stdout: {out!r}"
    assert err == "", f"при успехе stderr пустой, а там: {err!r}"

    code, out, err = call_main(["ModeGreen/nope"], FakeResponse(404, {"message": "Not Found"}))
    assert code == 3, f"404 → код 3, вернулось {code!r}"
    assert "ОШИБКА" in err and "не найден" in err, \
        f"404 → в stderr «ОШИБКА: репозиторий ModeGreen/nope не найден». stderr: {err!r}"
    assert "ModeGreen/nope" in err, f"в сообщении про 404 укажи имя репозитория. stderr: {err!r}"
    assert out == "", f"при ошибке stdout пустой, а там: {out!r}"

    code, out, err = call_main(["ModeGreen/devops-learning"],
                               error=requests.exceptions.ConnectionError("нет сети"))
    assert code == 3, f"нет сети → код 3, вернулось {code!r}"
    assert "ОШИБКА" in err and "нет сети" in err, f"нет сети → «ОШИБКА: <текст исключения>» в stderr. stderr: {err!r}"

    code, out, err = call_main(["ModeGreen/devops-learning"],
                               error=requests.exceptions.Timeout("слишком долго"))
    assert code == 3 and "ОШИБКА" in err, f"таймаут → код 3 и ОШИБКА в stderr. код {code!r}, stderr {err!r}"

    code, out, err = call_main(["ModeGreen/devops-learning"], FakeResponse(500, {}))
    assert code == 3 and "ОШИБКА" in err, f"код 500 → код 3 и ОШИБКА в stderr. код {code!r}, stderr {err!r}"

    # как отдельная программа: код выхода доходит до shell
    r = subprocess.run([sys.executable, str(here / "gh_check.py")], capture_output=True, text=True)
    assert r.returncode == 3, f"`python gh_check.py` без аргумента: код выхода {r.returncode}, ждали 3 (sys.exit(main()))"
    print("Шаг 5 ✅ main")


steps = {1: check_step1, 2: check_step2, 3: check_step3, 4: check_step4, 5: check_step5}
if step:
    steps[step]()
else:
    for f in steps.values():
        f()
    print("Все тесты прошли")
