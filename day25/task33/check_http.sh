#!/bin/bash
# Проверка адреса по коду ответа. Запуск: ./check_http.sh <url>
if [ $# -ne 1 ]; then
    echo "Usage: ./check_http.sh <url>" >&2
    exit 3
fi
max_time=5
url=$1
response=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$max_time" "$url")
curl_code=$?
if [ "$curl_code" -ne 0 ]; then
    echo "CRITICAL: <url> - no response (curl exit code $curl_code)"
    exit 2
fi
if [ "$response" -ge 200 ] && [ "$response" -lt 400 ]; then
    echo "OK: $url - HTTP $response"
else
    echo "CRITICAL: $url - HTTP $response"
    exit 2
fi