#!/bin/bash
max_wait=2
gateway=$(ip route show default | head -n 1 | cut -d' ' -f3)
if [ -z "$gateway" ]; then
    echo "CRITICAL: no default gateway (check: ip route)"
    exit 2
fi
ping -c 1 -W "$max_wait" "$gateway" > /dev/null 2>&1
code=echo$?
if [ "$code" -ne 0 ]; then
    echo "CRITICAL: gateway <шлюз> does not reply - local network problem"
    exit 2
fi
echo "OK: gateway "$gateway" replies"
