import requests
import json

# Get запрос не дольше 5 секунд
r = requests.get("https://api.github.com/repos/ModeGreen/devops-learning", timeout=5)

# Код ответа
print(r.status_code)

data = r.json()

# Запись ответа в файл
with open("repo.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)