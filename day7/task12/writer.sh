#!/bin/bash
# Задача 12: «живой» лог — дописывает строку в live.log раз в секунду, 30 секунд.
# Запуск: bash writer.sh   (в одном окне), а в другом смотришь live.log

cd "$(dirname "$0")" || exit 1
: > live.log
words=(alpha bravo charlie delta echo foxtrot golf hotel india juliet)
for i in $(seq 1 30); do
    if [ "$i" -eq 17 ]; then
        echo "$(date +%T) WARN deploy key: ${words[$(( (i * 7) % 10 ))]}-${i}" >> live.log
    else
        echo "$(date +%T) INFO heartbeat $i" >> live.log
    fi
    sleep 1
done
echo "$(date +%T) INFO writer finished" >> live.log
echo "writer.sh: закончил, 30 строк записано в live.log"
