#!/bin/bash
#Проверяет наличие термальных датчиков и выводит их показания
dir=/sys/class/thermal
count=0
for zone in "$dir"/thermal_zone*; do
    if [ -d "$zone" ]; then
        count=$((count + 1))
        name=$(cat "$zone"/type)
        temp=$(cat "$zone"/temp 2>/dev/null)
        if [ "$temp" = "" ]; then
            echo "$name: нет данных"
        else
            temp=$((temp / 1000))
            echo "$name: $temp °C"
        fi
    fi
done
if [ $count -eq 0 ]; then
    echo "ОШИБКА: нет датчиков температуры в $dir" >&2
    exit 1
fi