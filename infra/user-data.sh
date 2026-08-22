#!/bin/bash

set -euxo pipefail
exec > >(tee /var/log/lab-user-data.log | logger -t lab-user-data -s 2>/dev/console) 2>&1

dnf install -y nginx

printf '%s\n' \
  '<!doctype html>' \
  '<html lang="en">' \
  '<head><meta charset="utf-8"><title>Codyssey Cloud Web Lab</title></head>' \
  '<body><h1>Codyssey Cloud Web Lab</h1><p>Project: codyssey-06-1</p></body>' \
  '</html>' \
  > /usr/share/nginx/html/index.html

printf 'OK\n' > /usr/share/nginx/html/health

systemctl enable --now nginx
systemctl is-active nginx
curl --fail --silent --show-error http://localhost/
curl --fail --silent --show-error http://localhost/health
curl --fail --silent --show-error https://example.com/ >/dev/null

printf 'user-data-complete\n' > /var/tmp/lab-user-data-complete
