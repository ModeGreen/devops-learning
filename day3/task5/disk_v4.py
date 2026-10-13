import sys

servers = [
    {"name": "web-01",   "env": "prod",  "capacity": 120, "used": 50},
    {"name": "web-02",   "env": "prod",  "capacity": 120, "used": 90},
    {"name": "db-01",    "env": "prod",  "capacity": 240, "used": 230},
    {"name": "cache-01", "env": "stage", "capacity": 64,  "used": 60},
    {"name": "test-01",  "env": "stage", "capacity": 0,   "used": 10},
    {"name": "test-02",  "env": "prod", "capacity": 120,   "used": -5},
    {"name": "ci-01",    "env": "dev",   "capacity": 500, "used": 100},
]

THRESHOLDS = (75, 90)
warning, critical = THRESHOLDS

counts = {"OK": 0, "WARNING": 0, "CRITICAL": 0}

envs = set()

skipped_servers = []

critical_servers = []

highest_percentage = -1
highest_percentage_name = ""

for server in servers:
    if server["capacity"] <= 0 or server["capacity"] < server["used"] or server["used"] < 0:
        print(f"{server['name']} [{server['env']}]: SKIPPED - неверные данные")
        skipped_servers.append(server["name"])
        continue

    percent = server["used"] / server["capacity"] * 100
    if percent > highest_percentage:
        highest_percentage = percent
        highest_percentage_name = server["name"]

    if percent >= critical:
        status = "CRITICAL"
        counts["CRITICAL"] += 1
        envs.add(server["env"])
        critical_servers.append(server["name"])
    elif percent >= warning:
        status = "WARNING"
        counts["WARNING"] += 1
        envs.add(server["env"])
    else:
        status = "OK"
        counts["OK"] += 1
    print(f"{server['name']} [{server['env']}]: {percent:.1f}% — {status}")
    

print(f"=== Итого: {len(servers)} серверов ===")
print(f"OK: {counts['OK']}, WARNING: {counts['WARNING']}, CRITICAL: {counts['CRITICAL']}")
print(f'CRITICAL: '+", ".join(critical_servers))
print(f"Проблемные окружения: "+", ".join(sorted(envs)))
print(f"Пропущены: "+", ".join(skipped_servers))
print(f"Самый заполненный: {highest_percentage_name} ({highest_percentage:.1f}%)")

if counts["CRITICAL"] > 0:
    sys.exit(2)
elif counts["WARNING"] > 0:
    sys.exit(1)
else:
    sys.exit(0)