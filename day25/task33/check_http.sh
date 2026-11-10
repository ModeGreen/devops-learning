#!/bin/bash
# Проверка адреса по коду ответа. Запуск: ./check_http.sh <url>
max_time=5
url=$1
response=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$max_time" "$url")
if [ "$response" -ge 200 ] && [ "$response" -lt 400 ]; then
    echo "OK: $url - HTTP $response"
else
    echo "CRITICAL: $url - HTTP $response"
    exit 2
fi