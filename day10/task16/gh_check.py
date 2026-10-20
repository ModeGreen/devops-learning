import requests
import sys

def make_report(data):
    report = (f"{data["full_name"]}: звёзд {data["stargazers_count"]}, открытых issues {data["open_issues_count"]}, последний push {data["pushed_at"]}")
    return report

def fetch_repo(full_name):
    r = requests.get(f"https://api.github.com/repos/{full_name}", timeout=5)
    if r.status_code == 404:
        return None
    r.raise_for_status()
    return r.json()

def main():
    if len(sys.argv) > 1:
        full_name = sys.argv[1]
    else:
        print(f"ОШИБКА: Неверное число аргументов (получено: {len(sys.argv)}, ожидалось: 2)", file=sys.stderr)
        return 3

    try:
        repo = fetch_repo(full_name)
    except requests.exceptions.RequestException as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    if repo == None:
        print(f"ОШИБКА: репозиторий {full_name} не найден", file=sys.stderr)
        return 3

    print(make_report(repo))

    return 0

if __name__ == "__main__":
    sys.exit(main())
