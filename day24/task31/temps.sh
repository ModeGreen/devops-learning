#!/bin/bash
#Описание
dir=/sys/class/thermal
for zone in "$dir"/thermal_zone*; do
    name=$(cat "$zone"/type)
    echo "Получил имя"
    temp=$(cat "$zone"/temp)
    temp=$((temp / 1000))
    echo "$name: $temp °C"
done