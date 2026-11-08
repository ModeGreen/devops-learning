#!/bin/bash
#Прогон тестов
for f in tests/*.txt; do
    code=$(head -n 1 "$f")
    tail -n +2 "$f" | python3 disk_v3.py > /dev/null 2>&1
    real_code=$(echo $?)
    if [ "$code" -eq "$real_code" ]; then
        echo "PASS $f: код $code"
    else
        echo "FAIL $f: ждали $code, получили $real_code"
    fi
done