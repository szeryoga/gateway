FROM nginx:1.28-alpine

RUN apk add --no-cache python3 py3-yaml openssl

WORKDIR /app

RUN mkdir -p /app/scripts /app/config /app/nginx /var/www/certbot /etc/nginx/generated /etc/nginx/fallback

COPY scripts/generate_nginx_conf.py /app/scripts/generate_nginx_conf.py
COPY scripts/entrypoint.sh /app/scripts/entrypoint.sh

RUN chmod +x /app/scripts/entrypoint.sh /app/scripts/generate_nginx_conf.py

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
