import os
import yaml
import sys

def load_config(path):
    with open(path, encoding='utf-8') as f:
        data = yaml.safe_load(f)
    return data

def check_config(data):
    bad_lines = []
    for section in ("service", "database", "server"):
        if section not in data:
            bad_lines.append(f"CRITICAL: нет секции {section}")

    if "server" in data:
       port = data["server"].get("port")
       if not (type(port) is int and 1 <= port <= 65535):
           bad_lines.append(f"CRITICAL: неверный порт {port}")

    if "service" in data:
        if data["service"].get("debug"):
            bad_lines.append("WARNING: включён debug")
    return bad_lines

def get_exit_code(problems):
    for problem in problems:
        if problem.startswith("CRITICAL"):
            return 2
    if problems != []:
            return 1
    return 0

def main():

    try:
        source_file = sys.argv[1]
    except IndexError as e:
        print(f"ОШИБКА: {e} (нет файла для обработки)", file=sys.stderr)
        return 3

    try:
        data = (load_config(source_file))
    except (FileNotFoundError, PermissionError, yaml.YAMLError) as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    if not isinstance(data, dict):
        print("ОШИБКА: конфиг пуст или не является словарём", file=sys.stderr)
        return 3

    problems = check_config(data)

    if problems == []:
        print("OK: конфиг в порядке")
    else:
        print("\n".join(problems))
    
    return get_exit_code(problems)

if __name__ == "__main__":
    sys.exit(main())