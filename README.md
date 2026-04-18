# Gateway

Production-ready reverse proxy gateway на базе Nginx с генерацией `nginx.conf` из YAML-маршрутов и запуском в Docker.

## Что внутри

- Docker-контейнер с Nginx, Python и генератором конфига.
- Маршрутизация в [`config/routes.yml`](./config/routes.yml).
- Генерация итогового `/etc/nginx/nginx.conf` при старте контейнера.
- Проверка конфига через `nginx -t` перед запуском.
- HTTP to HTTPS redirect для всего трафика, кроме ACME HTTP-01 challenge.
- WebSocket support, proxy headers, default server и базовые production-настройки таймаутов.

## Структура

- `.env.example` — пример переменных окружения.
- `compose.yaml` — запуск `gateway` и подключение к external Docker network.
- `config/routes.yml` — декларативные маршруты по доменам.
- `scripts/generate_nginx_conf.py` — валидация YAML и генерация `nginx.conf`.
- `scripts/entrypoint.sh` — генерация конфига, `nginx -t`, запуск Nginx.
- `nginx/nginx.conf.template` — шаблон базового конфига.

## 1. Создать Docker network

Имя сети должно совпадать со значением `GATEWAY_NETWORK` в `.env`.

```bash
docker network create gateway-net
```

Проверьте, что ваши upstream-сервисы подключены к этой же сети и доступны по service name, например `tochka-backend`, `karabas-admin` и т.д.

## 2. Настроить `.env`

Скопируйте пример и при необходимости измените имя сети и порты:

```bash
cp .env.example .env
```

Пример:

```env
GATEWAY_NETWORK=gateway-net
GATEWAY_HTTP_PORT=80
GATEWAY_HTTPS_PORT=443
```

## 3. Подготовить каталоги для Certbot

```bash
mkdir -p certbot/www certbot/conf
```

`compose.yaml` монтирует:

- `./certbot/www` в `/var/www/certbot` для ACME HTTP-01 challenge
- `./certbot/conf` в `/etc/letsencrypt` для сертификатов

## 4. Запустить gateway

```bash
docker compose up -d --build
```

Проверка:

```bash
docker compose logs -f gateway
docker exec gateway nginx -t
```

Если `config/routes.yml` невалиден или итоговый `nginx.conf` некорректен, контейнер завершится с ошибкой на старте.

Если для домена сертификат еще не выпущен, gateway стартует с fallback self-signed сертификатом. Это позволяет поднять контейнер и пройти ACME HTTP-01 challenge по `80` порту до получения боевого сертификата.

## 5. Как добавить новый домен

Достаточно добавить новый блок в `config/routes.yml` и перезапустить контейнер:

```yaml
domains:
  - host: new-site.example.com
    routes:
      - path: /app
        upstream: http://new-frontend:80
      - path: /api
        upstream: http://new-backend:8000
```

После изменения:

```bash
docker compose restart gateway
```

## Формат маршрутов

Пример:

```yaml
domains:
  - host: tochka.etalonfood.com
    routes:
      - path: /app
        upstream: http://tochka-frontend:80
      - path: /admin
        upstream: http://tochka-admin:80
      - path: /api
        upstream: http://tochka-backend:8000

  - host: karabas.etalonfood.com
    routes:
      - path: /app
        upstream: http://karabas-frontend:80
      - path: /admin
        upstream: http://karabas-admin:80
      - path: /api
        upstream: http://karabas-backend:8000
```

Генератор валидирует:

- `host` не пустой
- `path` начинается с `/`
- комбинация `(host, path)` уникальна
- `upstream` начинается с `http://` или `https://`

Для каждого домена генерируются:

- HTTP server block на `80` с `/.well-known/acme-challenge/` и redirect на HTTPS
- HTTPS server block на `443` с сертификатом из `/etc/letsencrypt/live/<host>/`

## Выпуск сертификатов через Certbot

Используется `webroot`-режим: challenge-файлы пишутся в `./certbot/www`, а Nginx отдает их через `/.well-known/acme-challenge/`.

Перед выпуском сертификатов gateway должен уже работать и слушать `80` порт.

Пример для `tochka.etalonfood.com`:

```bash
docker run --rm \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  certbot/certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  -d tochka.etalonfood.com
```

Пример для `karabas.etalonfood.com`:

```bash
docker run --rm \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  certbot/certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  -d karabas.etalonfood.com
```

Оба домена одной командой:

```bash
docker run --rm \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  certbot/certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  -d tochka.etalonfood.com \
  -d karabas.etalonfood.com
```

После успешного выпуска перезапустите gateway или выполните reload:

```bash
docker exec gateway nginx -s reload
```

Для самого первого выпуска нужен именно перезапуск контейнера, чтобы генератор пересобрал `nginx.conf` и заменил fallback сертификат на путь `/etc/letsencrypt/live/<host>/...`:

```bash
docker compose restart gateway
```

После этого для всех последующих продлений достаточно обычного:

```bash
docker exec gateway nginx -s reload
```

## Автопродление сертификатов

Пример `cron`:

```cron
0 3 * * * cd /path/to/gateway && docker run --rm \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  certbot/certbot renew --webroot --webroot-path /var/www/certbot \
  && docker exec gateway nginx -s reload
```

Пример `systemd` unit:

```ini
[Unit]
Description=Renew Let's Encrypt certificates for gateway

[Service]
Type=oneshot
WorkingDirectory=/path/to/gateway
ExecStart=/usr/bin/docker run --rm \
  -v /path/to/gateway/certbot/www:/var/www/certbot \
  -v /path/to/gateway/certbot/conf:/etc/letsencrypt \
  certbot/certbot renew --webroot --webroot-path /var/www/certbot
ExecStartPost=/usr/bin/docker exec gateway nginx -s reload
```

Пример `systemd` timer:

```ini
[Unit]
Description=Run gateway certificate renewal twice daily

[Timer]
OnCalendar=*-*-* 03,15:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Если нужен reload только после успешного renewal, используйте `ExecStartPost`, как в примере выше, либо shell-обертку с проверкой кода возврата.

## Как это работает

1. Контейнер запускает `scripts/entrypoint.sh`.
2. `entrypoint.sh` создает fallback TLS-сертификат для `default_server`.
3. Затем запускается `scripts/generate_nginx_conf.py`.
4. Генератор читает `config/routes.yml`, валидирует его и собирает `/etc/nginx/nginx.conf`.
5. Выполняется `nginx -t`.
6. Если проверка успешна, стартует `nginx -g 'daemon off;'`.
