server_name = input("Имя сервера: ")

disk_capacity = float(input("Объем диска (ГБ): "))
if disk_capacity <= 0:
    print("Ошибка: Объем диска должен быть положительным числом.")
    exit(1)

used_space = float(input("Занятое место (ГБ): "))
if used_space < 0 or used_space > disk_capacity:
    print("Ошибка: Занятое место должно быть неотрицательным и не превышать объем диска.")
    exit(1)

available_space = disk_capacity - used_space
usage_percentage = (used_space / disk_capacity) * 100

print(f"Сервер: {server_name}")
print(f"Свободно: {available_space:.1f} ГБ из {disk_capacity:.1f} ГБ")
print(f"Заполнено: {usage_percentage:.1f}%")
if usage_percentage >= 90:
    print("Статус: CRITICAL — срочно освободить место")
elif usage_percentage >= 75:
    print("Статус: WARNING — скоро закончится место")
else:
    print("Статус: OK")