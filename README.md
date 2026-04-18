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
- `scripts/certbot.sh` — выпуск или перевыпуск сертификата Let’s Encrypt для одного домена.
- `nginx/nginx.conf.template` — шаблон базового конфига.

## 1. Создать Docker network

Имя сети должно совпадать со значением `GATEWAY_NETWORK` в `.env`.

Так как в `compose.yaml` используется `external` network, Docker Compose не создаст её автоматически. Если сети с именем из `GATEWAY_NETWORK` ещё нет, создайте её один раз вручную перед первым запуском gateway.

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
CERTBOT_EMAIL=admin@example.com
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

Маршруты работают как path-prefix gateway:

- запрос на `/admin` уходит в upstream как `/`
- запрос на `/admin/assets/app.js` уходит в upstream как `/assets/app.js`
- запрос на `/api/users` уходит в upstream как `/users`

## Выпуск сертификатов через Certbot

Используется `webroot`-режим: challenge-файлы пишутся в `./certbot/www`, а Nginx отдает их через `/.well-known/acme-challenge/`.

Для выпуска и перевыпуска сертификатов используйте helper-скрипт:

```bash
./scripts/certbot.sh <domain>
```

Скрипт делает следующее:

- подхватывает `.env`
- при отсутствии создает Docker network `${GATEWAY_NETWORK}`
- поднимает `gateway`, чтобы ACME challenge был доступен по `80` порту
- запускает `certbot` в `webroot`-режиме
- если сертификат выпускается впервые, выполняет `docker compose restart gateway`
- если сертификат уже существует и был обновлен, выполняет `docker exec gateway nginx -s reload`

Пример для `tochka.etalonfood.com`:

```bash
./scripts/certbot.sh tochka.etalonfood.com
```

Пример для `karabas.etalonfood.com`:

```bash
./scripts/certbot.sh karabas.etalonfood.com
```

Оба домена по очереди:

```bash
./scripts/certbot.sh tochka.etalonfood.com
./scripts/certbot.sh karabas.etalonfood.com
```

Скрипт сам выбирает правильное действие:

- первый выпуск: `docker compose restart gateway`
- перевыпуск или продление существующего сертификата: `docker exec gateway nginx -s reload`

## Автопродление сертификатов

Пример `cron`:

```cron
0 3 * * * cd /path/to/gateway && ./scripts/certbot.sh tochka.etalonfood.com && ./scripts/certbot.sh karabas.etalonfood.com
```

Пример `systemd` unit:

```ini
[Unit]
Description=Renew Let's Encrypt certificates for gateway

[Service]
Type=oneshot
WorkingDirectory=/path/to/gateway
ExecStart=/bin/sh -lc './scripts/certbot.sh tochka.etalonfood.com && ./scripts/certbot.sh karabas.etalonfood.com'
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

Скрипт сам выполняет `docker exec gateway nginx -s reload` после успешного обновления существующего сертификата. Для первичного выпуска он делает `docker compose restart gateway`, чтобы gateway пересобрал `nginx.conf` и переключился с fallback сертификата на настоящий.

## Как это работает

1. Контейнер запускает `scripts/entrypoint.sh`.
2. `entrypoint.sh` создает fallback TLS-сертификат для `default_server`.
3. Затем запускается `scripts/generate_nginx_conf.py`.
4. Генератор читает `config/routes.yml`, валидирует его и собирает `/etc/nginx/nginx.conf`.
5. Выполняется `nginx -t`.
6. Если проверка успешна, стартует `nginx -g 'daemon off;'`.
