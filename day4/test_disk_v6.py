import os
from disk_v6 import parse_line, load_servers

# parse_line: обычная строка
assert parse_line("web-01,prod,120,50") == {"name": "web-01", "env": "prod", "capacity": 120, "used": 50}

# parse_line: пробелы и \n по краям
assert parse_line("  db-01,prod,240,230\n") == {"name": "db-01", "env": "prod", "capacity": 240, "used": 230}

# parse_line: числа должны быть int, а не строками
server = parse_line("ci-01,dev,500,100")
assert type(server["capacity"]) == int
assert type(server["used"]) == int

# parse_line: отрицательное число тоже должно читаться
assert parse_line("test-02,prod,120,-5")["used"] == -5

# parse_line: пустые строки и комментарии -> None
assert parse_line("") is None
assert parse_line("\n") is None
assert parse_line("   ") is None
assert parse_line("# name,env,capacity,used") is None

# load_servers: временный файл с комментарием и пустой строкой
tmp = "_test_servers.txt"
with open(tmp, "w", encoding="utf-8") as f:
    f.write("# name,env,capacity,used\n")
    f.write("web-01,prod,120,50\n")
    f.write("\n")
    f.write("db-01,prod,240,230\n")

servers = load_servers(tmp)
os.remove(tmp)

assert len(servers) == 2
assert servers[0]["name"] == "web-01"
assert servers[1]["used"] == 230

print("Все тесты прошли")