mkdir -pv server/{logs,configs,backups,archive}
mv -v ./incoming/*.log* ./server/logs/
cp -v ./incoming/*.conf ./server/configs/
mv -v ./incoming/nginx.conf ./server/backups/nginx.conf.bak
mv -v ./incoming/app.conf ./server/backups/app.conf.bak
cp -av ./incoming/old_configs ./server/archive/
rm -rv ./incoming/old_configs/
rm -v ./incoming/cache_*.tmp
mv -v ./incoming/"report final.txt" ./server/report_final.txt
rmdir -v ./incoming/empty/
touch ./server/.cleaned_at
