#!/bin/bash
#Прогон тестов
passed=0
failed=0
for f in tests/*.txt; do
    code=$(head -n 1 "$f")
    tail -n +2 "$f" | python3 disk_v3.py > /dev/null 2>&1
    real_code=$(echo $?)
    if [ "$code" -eq "$real_code" ]; then
        passed=$((passed + 1))
        echo "PASS $f: код $code"
    else
        failed=$((failed + 1))
        echo "FAIL $f: ждали $code, получили $real_code"
    fi
done
all_tests=$((passed + failed))
echo "Пройдено: $passed" из $all_tests, провалено: $failed
if [ "$failed" -eq 0 ]; then
    exit 0
else
    exit 1
fi