import sys
from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess


def get_hostname():
    try:
        result = subprocess.run(["hostname"], capture_output=True, text=True)
        name = result.stdout.strip()
    except FileNotFoundError:
        name = "unknown"
    return name

def is_invalid(usage):
    return usage["capacity"] <= 0 or not 0 <= usage["used"] <= usage["capacity"]

def get_percent(mount):
    return mount["used"] / mount["capacity"] * 100

def get_status(percent, warning=75, critical=90):
    if percent >= critical:
        return "CRITICAL"
    if percent >= warning:
        return "WARNING"
    return "OK"

def get_exit_code(counts):
    if counts["CRITICAL"] > 0:
        return 2
    if counts["WARNING"] > 0:
        return 1
    return 0

def load_mounts(path):
    mounts = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                    continue
            else:
                mounts.append(line)
    return mounts

def get_disk_usage(mount):
    try:
        usage = shutil.disk_usage(mount)
        total = usage.total / 1024**3
        used = usage.used / 1024**3
        return {"name": mount, "capacity": total, "used": used}
    except (FileNotFoundError, PermissionError):
        return None

def read_threshold(name, default):
    value = os.environ.get(name, default)
    try:
        value = int(value)
    except ValueError:
        raise ValueError(f"'{name}' должно быть целым числом, получено: '{value}'")
    return value

def get_thresholds():
    warning = read_threshold("DISK_WARNING", "75")
    critical = read_threshold("DISK_CRITICAL", "90")
    if not 0 < warning < critical <= 100:
        raise ValueError(f"нужно 0 < WARNING < CRITICAL <= 100, получено: 0 < {warning} < {critical}")
    return warning, critical

def main():

    # Заводим переменные
    script_dir = Path(__file__).parent
    counts = {"OK": 0, "WARNING": 0, "CRITICAL": 0}
    skipped_mounts = []
    critical_mounts = []
    report = []

    # Получаем пороговые значения
    try:
        warning, critical = get_thresholds()
    except ValueError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3
    
    highest_percentage = -1
    highest_percentage_name = ""
    mounts_file = sys.argv[1] if len(sys.argv) > 1 else script_dir / "mounts.txt"

    try:
        mounts = load_mounts(mounts_file)
    except FileNotFoundError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    for mount_path in mounts:

        mount = get_disk_usage(mount_path)
        if not mount:
            report.append(f"{mount_path}: SKIPPED - нет такого пути")
            skipped_mounts.append(mount_path)
            continue
        elif is_invalid(mount):
            report.append(f"{mount['name']}: SKIPPED - неверные данные")
            skipped_mounts.append(mount["name"])
            continue

        percent = get_percent(mount)
        if percent > highest_percentage:
            highest_percentage = percent
            highest_percentage_name = mount["name"]

        status = get_status(percent, warning, critical)
        if status == "CRITICAL":
            counts["CRITICAL"] += 1
            critical_mounts.append(mount["name"])
        elif status == "WARNING":
            counts["WARNING"] += 1
        else:
            counts["OK"] += 1
        report.append(f"{mount['name']}: {percent:.1f}%  ({mount['used']:.1f} из {mount['capacity']:.1f} ГБ) — {status}")
    
    report.append(f"=== Итого: {len(mounts)} дисков ===")
    report.append(f"OK: {counts['OK']}, WARNING: {counts['WARNING']}, CRITICAL: {counts['CRITICAL']}")
    if counts["CRITICAL"] > 0:
        report.append(f"CRITICAL: {', '.join(critical_mounts)}")
    report.append(f"Пропущены: "+", ".join(skipped_mounts))
    report.append(f"Самый заполненный: {highest_percentage_name} ({highest_percentage:.1f}%)")

    report = "\n".join(report)

        # Логируем запуск программы
    try:
        with open(script_dir/"report.log", "a", encoding="utf-8") as f:
            host_name = get_hostname()
            f.write(f"=== Запуск {datetime.now().strftime("%Y-%m-%d %H:%M:%S")} на {host_name} ===\n")
            f.write(report + "\n")
    except PermissionError as e:
        print(f"ВНИМАНИЕ: не удалось записать лог: {e}", file=sys.stderr)
    
    print(report)

    return get_exit_code(counts)

if __name__ == "__main__":
    sys.exit(main())