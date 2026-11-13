#!/bin/bash
max_wait=2
internet_ip=1.1.1.1
internet_name=one.one.one.one
gateway=$(ip route show default | head -n 1 | cut -d' ' -f3)
if [ -z "$gateway" ]; then
    echo "CRITICAL: no default gateway (check: ip route)"
    exit 2
fi
ping -c 1 -W "$max_wait" "$gateway" > /dev/null 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "CRITICAL: gateway "$gateway" does not reply - local network problem"
    exit 2
fi
echo "OK: gateway "$gateway" replies"
ping -c 1 -W "$max_wait" "$internet_ip" > /dev/null 2>&1
code=$?
if [ "$code" -ne 0 ]; then
    echo "CRITICAL: internet $internet_ip does not reply - router or provider problem"
    exit 2
fi
echo "OK: internet "$internet_ip" replies"
ping -c 1 -W "$max_wait" "$internet_name" > /dev/null 2>&1
code=$?
if [ "$code" -eq 0 ]; then
    echo "OK: name $internet_name resolves and replies"
elif [ "$code" -eq 1 ]; then
    echo "CRITICAL: name $internet_name resolves but does not reply"
    exit 2
else
    echo "CRITICAL: name $internet_name does not resolve - DNS problem"
    exit 2
fi
