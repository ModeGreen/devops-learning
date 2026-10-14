import sys
from pathlib import Path
import os

def parse_line(line):
    line = line.split()
    if not len(line) == 10:
        raise ValueError(f"ОШИБКА: неверное число аргументов строки - {len(line)}")
    request = {"ip": line[0], "method": line[5].strip('"'), "path": line[6], "status": line[8], "size": line[9]}
    try:
        request["status"] = int(request["status"])
        request["size"] = int(request["size"])
    except ValueError:
        raise ValueError(f"Ошибка: от 'статус' и 'код' ожидался тип 'int', получены {type(request["status"])} и {type(request["size"])}")
    return request

def load_requests(path):
    requsts = []
    bad_count = 0
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    request = parse_line(line)
                except ValueError:
                    bad_count += 1
                    continue
                requsts.append(request)
    except FileNotFoundError as e:
        raise FileNotFoundError(f"ОШИБКА: {e}")
    return requsts, bad_count

def get_error_rate(requests):
    percent_of_5xx = 0.0
    count_of_5xx = 0
    for request in requests:
        if request["status"] >= 500:
            count_of_5xx += 1
    if count_of_5xx == 0.0:
        return count_of_5xx
    percent_of_5xx = count_of_5xx / len(requests) * 100
    return percent_of_5xx

def get_top_ip(requests):    
    top_ip_calls = 0
    top_ip = ""
    for request in requests:
        ip_calls = 0
        ip = request["ip"]
        for i in requests:
            if i["ip"] == ip:
                ip_calls += 1
        if ip_calls > top_ip_calls:
            top_ip_calls = ip_calls
            top_ip = ip
    return top_ip, top_ip_calls

def get_max_error_rate():
    max_error_rate = os.environ.get("LOG_MAX_ERROR_RATE", 5)
    try:
        max_error_rate = int(max_error_rate)
    except ValueError:
        raise ValueError("LOG_MAX_ERROR_RATE")
    if not 0 <= max_error_rate <= 100:
        raise ValueError("LOG_MAX_ERROR_RATE")
    return max_error_rate

def count_statuses(requests):
    count = {}
    for request in requests:
        count[request["status"]] = count.get(request["status"], 0) + 1
    return count

def get_exit_code(error_rate, max_rate, bad_count):
    if error_rate > max_rate:
        return 2
    elif bad_count > 0:
        return 1
    else:
        return 0
    

def main():
    report = []
    script_dir = Path(__file__).parent
    source_path = sys.argv[1] if len(sys.argv) > 1 else script_dir / "access.log"

    try:
        requests, bad_count = load_requests(source_path)
    except FileNotFoundError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    try:
        max_rate = get_max_error_rate()
    except ValueError as e:
        print(f"ОШИБКА: {e}", file=sys.stderr)
        return 3

    status_counts = (count_statuses(requests))
    sorted_status_counts = sorted(status_counts)

    top_ip, top_ip_calls = get_top_ip(requests)

    error_rate = get_error_rate(requests)
    exit_code = get_exit_code(error_rate, max_rate, bad_count)

    report.append(f"=== Анализ {os.path.basename(source_path)} ===")
    report.append(f"Запросов: {len(requests)} (битых строк: {bad_count})")
    report.append(f"Коды ответа:")
    for status in sorted_status_counts:
        report.append(f"{status} {status_counts[status]}")
    report.append(f"Самый активный IP: {top_ip} ({top_ip_calls} запросов)")
    report.append(f"Ошибки 5xx: {error_rate:.1f}% (порог {max_rate}%)")
    if exit_code == 2:
        report.append(f"Статус: CRITICAL")
    elif exit_code == 1:
        report.append(f"Статус: WARNING")
    else:
        report.append(f"Статус: OK")
    
    report = "\n".join(report)

    print(report)

    return exit_code

if __name__ == "__main__":
    sys.exit(main())