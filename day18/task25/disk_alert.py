import json
import os
import sys
from pathlib import Path
import subprocess

def get_df_output():
    result = subprocess.run(["df", "-P"], capture_output=True, text=True)
    return result.stdout

def is_real_disk(filesystem):
    if filesystem.startswith('/dev/') and not filesystem.startswith('/dev/loop'):
        return True
    else:
        return False

def parse_df(text):
    mounts = []
    for line in text.splitlines():
        if line.startswith('Filesystem'):
            continue
        line = line.split()
        if not is_real_disk(line[0]):
            continue
        name = line[5]
        used = int(line[2])/1024**2
        total = int(line[1])/1024**2
        mounts.append({"name": name, "used_gb": used, "total_gb": total})
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
    disks_file = sys.argv[1] if len(sys.argv) > 1 else script_dir / "disks.json"

    try:
        disks = load_disks(disks_file)
    except (FileNotFoundError, json.decoder.JSONDecodeError) as e:
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
