from disk_v5 import is_invalid, get_percent, get_status, get_exit_code

print("Начинаю тесты")

# get_status
assert get_status(74.9) == "OK"
assert get_status(75) == "WARNING"
assert get_status(89.9) == "WARNING"
assert get_status(90) == "CRITICAL"
assert get_status(80, critical=80) == "CRITICAL"

print("get_status протестирован")

# is_valid
servers = [
    {"capacity": 100, "used": 50},
    {"capacity": 0, "used": 10},
    {"capacity": 100, "used": -5},
    {"capacity": 100, "used": 150},
]

assert is_invalid(servers[0]) == False
assert is_invalid(servers[1]) == True
assert is_invalid(servers[2]) == True
assert is_invalid(servers[3]) == True

print("is_invalid протестирован")

# get_exit_code
counts = [
    {"OK": 3, "WARNING": 0, "CRITICAL": 0},
    {"OK": 2, "WARNING": 1, "CRITICAL": 0},
    {"OK": 1, "WARNING": 1, "CRITICAL": 1},
]

assert get_exit_code(counts[0]) == 0
assert get_exit_code(counts[1]) == 1
assert get_exit_code(counts[2]) == 2

print("Все тесты прошли")