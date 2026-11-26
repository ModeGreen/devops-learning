#!/bin/bash
# Checks that a DNS resolver returns the expected address for a name.
#./dns_check.sh <name> <expected_ip>
name=$1
expected=$2
max_wait=2
resolver=1.1.1.1
if [ $# -ne 2 ]; then
    echo "Usage: ./dns_check.sh <name> <expected_ip>" >&2
    exit 3
fi
answer=$(dig +short +time="$max_wait" +tries=1 -t A @"$resolver" "$name")
code=$?
if [ "$code" -ne 0 ]; then
    echo "CRITICAL: $resolver does not reply"
    exit 2
fi
if [[ -z "$answer" ]]; then
    echo "CRITICAL: $resolver has no address for $name"
    exit 2
fi
one_line_answer=$(paste -sd ' ' - <<< "$answer")
if grep -qxF "$expected" <<< "$answer"; then
    echo "OK: $resolver resolves $name to $expected"
    exit 0
else
    echo "CRITICAL: $resolver resolves $name to $one_line_answer, expected $expected"
    exit 2
fi
