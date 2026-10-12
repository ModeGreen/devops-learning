import sys

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

def main():
    servers = [
        {"name": "web-01",   "env": "prod",  "capacity": 120, "used": 50},
        {"name": "web-02",   "env": "prod",  "capacity": 120, "used": 90},
        {"name": "db-01",    "env": "prod",  "capacity": 240, "used": 230},
        {"name": "cache-01", "env": "stage", "capacity": 64,  "used": 60},
        {"name": "test-01",  "env": "stage", "capacity": 0,   "used": 10},
        {"name": "test-02",  "env": "prod", "capacity": 120,   "used": -5},
        {"name": "ci-01",    "env": "dev",   "capacity": 500, "used": 100},
    ]

    counts = {"OK": 0, "WARNING": 0, "CRITICAL": 0}

    envs = set()

    skipped_servers = []

    critical_servers = []

    highest_percentage = -1
    highest_percentage_name = ""
    for server in servers:
        if is_invalid(server):
            print(f"{server['name']} [{server['env']}]: SKIPPED - неверные данные")
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
        print(f"{server['name']} [{server['env']}]: {percent:.1f}% — {status}")
    
    print(f"=== Итого: {len(servers)} серверов ===")
    print(f"OK: {counts['OK']}, WARNING: {counts['WARNING']}, CRITICAL: {counts['CRITICAL']}")
    print(f"CRITICAL: {', '.join(critical_servers)}")
    print(f"Проблемные окружения: "+", ".join(sorted(envs)))
    print(f"Пропущены: "+", ".join(skipped_servers))
    print(f"Самый заполненный: {highest_percentage_name} ({highest_percentage:.1f}%)")

    return get_exit_code(counts)

if __name__ == "__main__":
    sys.exit(main())