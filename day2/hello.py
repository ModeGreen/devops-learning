server = "web-01"
cores = 8
load = 0.756

print("Привет, сервер!")
print(f"Сервер {server}: {cores} ядер, загрузка {load * 100:.1f}%")
print(type(server), type(cores), type(load))