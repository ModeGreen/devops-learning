import sys

serv_num = int(input("Сколько серверов проверить? "))

if serv_num <= 0:
    print("Ошибка. Невозможное число серверов.")
    sys.exit(3)

num_warning = 0
num_critical = 0
num_ok = 0
highest_percentage = -1
highest_percentage_name = ""

for num in range(1, serv_num + 1):
    print(f"--- Сервер {num} из {serv_num} ---")

    server_name = input("Имя сервера: ")

    disk_capacity = float(input("Объем диска (ГБ): "))
    while disk_capacity <= 0:
        disk_capacity = float(input("Невозможное значение.\nВведите объем диска (ГБ): "))

    used_space = float(input("Занятое место (ГБ): "))
    while used_space < 0 or used_space > disk_capacity:
        used_space = float(input("Невозможное значение.\nВведите занятое место (ГБ): "))

    available_space = disk_capacity - used_space
    usage_percentage = (used_space / disk_capacity) * 100
    if highest_percentage < usage_percentage:
        highest_percentage = usage_percentage
        highest_percentage_name = server_name

    print(f"Сервер: {server_name}")
    print(f"Свободно: {available_space:.1f} ГБ из {disk_capacity:.1f} ГБ")
    print(f"Заполнено: {usage_percentage:.1f}%")

    if usage_percentage >= 90:
        print("Статус: CRITICAL — срочно освободить место")
        num_critical += 1
    elif usage_percentage >= 75:
        print("Статус: WARNING — скоро закончится место")
        num_warning += 1
    else:
        print("Статус: OK")
        num_ok += 1

print(f"=== Проверено серверов: {serv_num} ===")
print(f"OK: {num_ok}, WARNING: {num_warning}, CRITICAL: {num_critical}")
print(f"Самый заполненный: {highest_percentage_name} ({highest_percentage:.1f}%)")

if num_critical > 0:
    sys.exit(2)
elif num_warning > 0:
    sys.exit(1)
else:
    sys.exit(0)