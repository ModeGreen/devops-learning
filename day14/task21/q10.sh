cut -d' ' -f1 shop/logs/access.log | sort | uniq -c | sort -rn | head -n 3 > shop/reports/top-ip.txt
