server_name = input("Имя сервера: ")
disk_capacity = float(input("Объем диска (ГБ): "))
used_space = float(input("Занятое место (ГБ): "))
available_space = disk_capacity - used_space
usage_percentage = (used_space / disk_capacity) * 100

print(f"Сервер: {server_name}")
print(f"Свободно: {available_space:.1f} ГБ из {disk_capacity:.1f} ГБ")
print(f"Заполнено: {usage_percentage:.1f}%")