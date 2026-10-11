#!/bin/bash
# Прогоняет все tests/*.txt через disk_v3.py.
# Первая строка файла — ожидаемый код возврата, остальные — ввод.

passed=0
failed=0

for test_file in tests/*.txt; do
    expected=$(head -n 1 "$test_file")
    output=$(tail -n +2 "$test_file" | python3 disk_v3.py 2>&1)
    actual=$?

    if [ "$actual" -eq "$expected" ]; then
        echo "✅ $test_file — код $actual"
        passed=$((passed + 1))
    else
        echo "❌ $test_file — ожидался $expected, получен $actual"
        failed=$((failed + 1))
    fi
    echo "$output" | tail -n 3 | sed 's/^/     /'
done

echo "=== Пройдено: $passed, провалено: $failed ==="
[ "$failed" -eq 0 ]
