"""disk_alert.py — проверяет заполненность дисков из JSON-файла
и записывает проблемные диски в alerts.json.

Запуск:  python3 disk_alert.py [файл_с_дисками]   (по умолчанию disks.json)
Пороги:  переменные окружения DISK_WARNING (75) и DISK_CRITICAL (90).
Коды выхода (как у Nagios): 0 — OK, 1 — WARNING, 2 — CRITICAL, 3 — ошибка.
"""
import json
import os
import sys
from pathlib import Path


def load_disks(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def get_thresholds():
    warning = int(os.environ.get("DISK_WARNING", 75))
    critical = int(os.environ.get("DISK_CRITICAL", 90))
    return warning, critical


def get_status(percent, warning, critical):
    if percent >= critical:
        return "CRITICAL"
    if percent >= warning:
        return "WARNING"
    return "OK"


def find_alerts(disks, warning, critical):
    alerts = []
    for disk in disks:
        percent = disk["used_gb"] / disk["total_gb"] * 100
        status = get_status(percent, warning, critical)
        if status != "OK":
            alerts.append({"name": disk["name"], "percent": round(percent, 1), "status": status})
    return alerts


def get_exit_code(alerts):
    code = 0
    for alert in alerts:
        if alert["status"] == "CRITICAL":
            return 2
        code = 1
    return code


def main():
    script_dir = Path(__file__).parent
    disks_file = sys.argv[1] if len(sys.argv) > 1 else script_dir / "disks.json"

    try:
        disks = load_disks(disks_file)
    except FileNotFoundError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    warning, critical = get_thresholds()
    alerts = find_alerts(disks, warning, critical)

    with open(script_dir / "alerts.json", "w", encoding="utf-8") as f:
        json.dump(alerts, f, indent=2, ensure_ascii=False)

    print(f"Проверено дисков: {len(disks)}, проблемных: {len(alerts)}")
    for alert in alerts:
        print(f"  {alert['name']}: {alert['percent']}% — {alert['status']}")

    return get_exit_code(alerts)


if __name__ == "__main__":
    sys.exit(main())
