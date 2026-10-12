import sys
from datetime import datetime

def is_invalid(server):
    return server["capacity"] <= 0 or not 0 <= server["used"] <= server["capacity"]

def get_percent(server):
    return server["used"] / server["capacity"] * 100

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

def parse_line(line):
    line = line.strip()
    if not line or line.startswith("#"):
        return
    name, env, capacity, used = line.split(",")
    capacity = int(capacity)
    used = int(used)
    return {"name": name, "env": env, "capacity": capacity, "used": used}

def load_servers(path):
    servers = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parsed_line = parse_line(line)
            if parsed_line == None:
                continue
            else:
                servers.append(parsed_line)
    return servers


def main():

    with open("report.log", "a", encoding="utf-8") as f:
        f.write(f"=== Запуск {datetime.now().strftime("%Y-%m-%d %H:%M:%S")} ===\n")
    
    sys.argv
    path = sys.argv[1] if len(sys.argv) > 1 else "servers.txt"

    counts = {"OK": 0, "WARNING": 0, "CRITICAL": 0}

    envs = set()

    skipped_servers = []

    critical_servers = []

    report = []

    servers = load_servers(path)

    highest_percentage = -1
    highest_percentage_name = ""

    for server in servers:
        if is_invalid(server):
            report.append(f"{server['name']} [{server['env']}]: SKIPPED - неверные данные")
            skipped_servers.append(server["name"])
            continue

        percent = get_percent(server)
        if percent > highest_percentage:
            highest_percentage = percent
            highest_percentage_name = server["name"]

        status = get_status(percent)

        if status == "CRITICAL":
            counts["CRITICAL"] += 1
            envs.add(server["env"])
            critical_servers.append(server["name"])
        elif status == "WARNING":
            counts["WARNING"] += 1
            envs.add(server["env"])
        else:
            counts["OK"] += 1
        report.append(f"{server['name']} [{server['env']}]: {percent:.1f}% — {status}")
    
    report.append(f"=== Итого: {len(servers)} серверов ===")
    report.append(f"OK: {counts['OK']}, WARNING: {counts['WARNING']}, CRITICAL: {counts['CRITICAL']}")
    report.append(f"CRITICAL: {', '.join(critical_servers)}")
    report.append(f"Проблемные окружения: "+", ".join(sorted(envs)))
    report.append(f"Пропущены: "+", ".join(skipped_servers))
    report.append(f"Самый заполненный: {highest_percentage_name} ({highest_percentage:.1f}%)")

    report = "\n".join(report)
    print(report)

    with open("report.log", "a", encoding="utf-8") as f:
        f.write(report + "\n")

    return get_exit_code(counts)

if __name__ == "__main__":
    sys.exit(main())