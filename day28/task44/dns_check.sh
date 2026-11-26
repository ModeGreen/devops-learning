#!/bin/bash
# Checks that a DNS resolver returns the expected address for a name.
# ./dns_check.sh <name> <expected_ip>
max_wait=2
resolvers="1.1.1.1 8.8.8.8 9.9.9.9"
checked=0
problems=0
if [ $# -ne 2 ]; then
    echo "Usage: ./dns_check.sh <name> <expected_ip>" >&2
    exit 3
fi
name=$1
expected=$2
for resolver in $resolvers; do
    answer=$(dig +short +time="$max_wait" +tries=1 -t A @"$resolver" "$name")
    code=$?
    if [ "$code" -ne 0 ]; then
        echo "CRITICAL: $resolver does not reply"
        problems=$((problems + 1))
    elif [[ -z "$answer" ]]; then
        echo "CRITICAL: $resolver has no address for $name"
        problems=$((problems + 1))
    elif grep -qxF "$expected" <<< "$answer"; then
        echo "OK: $resolver resolves $name to $expected"
    else
        one_line_answer=$(paste -sd ' ' - <<< "$answer")
        echo "CRITICAL: $resolver resolves $name to $one_line_answer, expected $expected"
        problems=$((problems + 1))
    fi
    checked=$((checked + 1))
done
echo "Checked $checked resolvers. Problems: $problems"
if [ $problems -ne 0 ]; then
    exit 2
fi
