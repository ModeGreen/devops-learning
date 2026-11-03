"""disk_alert.py — проверяет заполненность дисков из JSON-файла
и записывает проблемные диски в alerts.json.

Запуск:  python3 disk_alert.py
Пороги:  загружаются из disk_alert.yaml, который лежит рядом со скриптом, и передаются в find_alerts.
Коды выхода (как у Nagios): 0 — OK, 1 — WARNING, 2 — CRITICAL, 3 — ошибка.
"""

import json
import os
import sys
from pathlib import Path
import subprocess
import yaml

def load_config(path):
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data

def get_findmnt_output():
    result = subprocess.run(["findmnt", "-D", "-O", "rw", "-b", "-J"], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"findmnt завершился с кодом {result.returncode}: {result.stderr.strip()}")
    return result.stdout

def is_real_disk(source):
    if source.startswith('/dev/') and not source.startswith('/dev/loop'):
        return True
    else:
        return False

def parse_findmnt(data):
    data = json.loads(data)["filesystems"]
    mounts = []
    for mount in data:
        if not is_real_disk(mount["source"]):
            continue
        used_gb = int(mount["used"]) / 1024**3
        total_gb = int(mount["size"]) / 1024**3
        mounts.append({"name": mount["target"], "used_gb": used_gb, "total_gb": total_gb})
    return mounts

def remove_ignored(disks, config):
    ignored_removed = []
    for disk in disks:
        if not disk["name"] in config.get("ignore", []):
            ignored_removed.append(disk)
    return ignored_removed

def get_disk_thresholds(name, config):
    warning = config["default"]["warning"]
    critical = config["default"]["critical"]
    if "disks" in config:
        if name in config["disks"]:
            warning = config["disks"][name].get("warning", config["default"]["warning"])
            critical = config["disks"][name].get("critical", config["default"]["critical"])
    if type(warning) != int or type(critical) != int:
        raise ValueError(f"{name}: warning и critical должны быть int")
    if not critical > warning:
        raise ValueError(f"{name}: warning ({warning}) должен быть меньше critical ({critical})")
    return warning, critical

def get_status(percent, warning, critical):
    if percent >= critical:
        return "CRITICAL"
    if percent >= warning:
        return "WARNING"
    return "OK"

def find_alerts(disks, config):
    alerts = []
    for disk in disks:
        warning, critical = get_disk_thresholds(disk["name"], config)
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
    try:
        config = load_config(os.environ.get("DISK_ALERT_CONFIG", script_dir / "disk_alert.yaml"))
    except (FileNotFoundError, yaml.parser.ParserError) as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    try:
        disks = parse_findmnt(get_findmnt_output())
    except RuntimeError as e:
        print(f"ОШИБКА: {e} ", file=sys.stderr)
        return 3

    disks = remove_ignored(disks, config)

    try:
        alerts = find_alerts(disks, config)
    except ValueError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    with open(script_dir / "alerts.json", "w", encoding="utf-8") as f:
        json.dump(alerts, f, indent=2, ensure_ascii=False)

    print(f"Проверено дисков: {len(disks)}, проблемных: {len(alerts)}")
    for alert in alerts:
        print(f"  {alert['name']}: {alert['percent']}% — {alert['status']}")

    return get_exit_code(alerts)

if __name__ == "__main__":
    sys.exit(main())
