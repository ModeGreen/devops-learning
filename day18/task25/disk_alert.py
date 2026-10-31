import json
import os
import sys
from pathlib import Path
import subprocess

def get_findmnt_output():
    result = subprocess.run(["findmnt", "-D", "-O", "rw", "-b", "-J"], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{result.stderr.strip()}")
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

    try:
        disks = parse_findmnt(get_findmnt_output())
    except RuntimeError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    try:
        warning, critical = get_thresholds()
        alerts = find_alerts(disks, warning, critical)
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
