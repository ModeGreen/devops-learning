import sys
import subprocess
import json

def get_ip_json():
    result = subprocess.run(["ip", "-j", "addr"], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"findmnt завершился с кодом {result.returncode}: {result.stderr.strip()}")
    return result.stdout

def parse_addresses(text):
    data = json.loads(text)
    adresses = []
    for interface in data:
        name = interface["ifname"]
        for adress in interface["addr_info"]:
            if adress["family"] == "inet":
                addr_with_pref = (f"{adress["local"]}/{str(adress["prefixlen"])}")
                adresses.append((name, addr_with_pref))
    return adresses

def main():
    adresses = parse_addresses(get_ip_json())
    for adress in adresses:
        print(f"{adress[0]}: {adress[1]}")

if __name__ == "__main__":
    sys.exit(main())
