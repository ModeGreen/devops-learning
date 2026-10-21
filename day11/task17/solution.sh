sudo groupadd shop
sudo useradd --system --gid shop --shell /usr/sbin/nologin shopapp
sudo chown shopapp:shop /srv/shop/.env
sudo chown -R shopapp:shop /srv/shop/logs
sudo chgrp shop /srv/shop/config.yaml
chmod 640 /srv/shop/config.yaml
sudo usermod -dG shop mondegrin