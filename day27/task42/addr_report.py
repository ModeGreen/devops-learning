import sys
import subprocess
import json
import ipaddress

NETWORK_KINDS = [
    ('127.0.0.0/8', 'loopback'),
    ('169.254.0.0/16', 'link-local'),
    ('10.0.0.0/8', 'private'),
    ('172.16.0.0/12', 'private'),
    ('192.168.0.0/16', 'private'),
    ('100.64.0.0/10', 'shared')]

KIND_NOTES = {
    "loopback": "this machine only",
    "link-local": "same link only",
    "private": "not routed on the internet",
    "shared": "Tailscale or provider CGNAT",
    "public": "routed on the internet",
}

def get_network(address):
    interface = ipaddress.ip_interface(address)
    return str(interface.network)

def get_kind(address):
    ip = ipaddress.ip_interface(address).ip
    for network, kind in NETWORK_KINDS:
        if ip in ipaddress.ip_network(network):
            return kind
    return "public"

def format_line(name, address):
    net = get_network(address)
    kind = get_kind(address)
    note = KIND_NOTES[kind]
    return f"{name}: {address} in {net} - {kind}, {note}"


def get_ip_json():
    result = subprocess.run(["ip", "-j", "addr"], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ip -j addr failed with code {result.returncode}: {result.stderr.strip()}")
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
    try:
        addresses = parse_addresses(get_ip_json())
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
    for address in addresses:
        print(format_line(address[0], address[1]))

if __name__ == "__main__":
    sys.exit(main())
