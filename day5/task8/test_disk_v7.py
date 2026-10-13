import os
from pathlib import Path
from disk_v7 import load_mounts, get_disk_usage, get_thresholds, get_hostname

# load_mounts: комментарии и пустые строки пропускаются, пробелы и \n обрезаются
tmp = Path(__file__).parent / "_test_mounts.txt"
tmp.write_text("# точки монтирования\n/\n\n  /home  \n", encoding="utf-8")
mounts = load_mounts(tmp)
tmp.unlink()
assert mounts == ["/", "/home"]

# get_disk_usage: корень существует всегда
disk = get_disk_usage("/")
assert disk["name"] == "/"
assert disk["capacity"] > 0
assert 0 <= disk["used"] <= disk["capacity"]
assert disk["capacity"] < 100_000   # в гигабайтах, а не в байтах

# get_disk_usage: несуществующий путь -> None, без падения
assert get_disk_usage("/no/such/mount") is None

# get_thresholds: по умолчанию
os.environ.pop("DISK_WARNING", None)
os.environ.pop("DISK_CRITICAL", None)
assert get_thresholds() == (75, 90)

# get_thresholds: из переменных окружения, числа, а не строки
os.environ["DISK_WARNING"] = "60"
os.environ["DISK_CRITICAL"] = "80"
assert get_thresholds() == (60, 80)
os.environ.pop("DISK_WARNING")
os.environ.pop("DISK_CRITICAL")

# get_hostname: непустая строка без \n на конце
host = get_hostname()
assert type(host) == str
assert host != ""
assert not host.endswith("\n")

print("Все тесты прошли")