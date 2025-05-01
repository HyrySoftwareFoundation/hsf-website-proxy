#!/bin/bash

echo "Running base image entrypoint..."
bash /docker-entrypoint.sh "$@"
echo "Base image entrypoint finished"

echo "Renewing certificate for $HSF_CONTACT site $HSF_DOMAIN with key size $HSF_RSA_KEY_SIZE..."
certbot certonly --webroot -w /var/www/certbot \
    --staging --email "$HSF_CONTACT" \
    -d "$HSF_DOMAIN" -d "www.$HSF_DOMAIN" \
    --rsa-key-size $HSF_RSA_KEY_SIZE --agree-tos \
    --force-renewal
echo "Certbot finished"

echo "Reloading nginx"
nginx -s reload
echo "nginx reloaded"

echo "Starting certbot and nginx reload jobs"
/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;' &
/bin/sh -c 'while :; do sleep 6h & wait $${!}; nginx -s reload; done' &
echo "Jobs started"
