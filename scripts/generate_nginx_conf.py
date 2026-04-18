#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate nginx.conf from config/routes.yml"
    )
    parser.add_argument(
        "--routes",
        default="/app/config/routes.yml",
        help="Path to routes YAML file",
    )
    parser.add_argument(
        "--template",
        default="/app/nginx/nginx.conf.template",
        help="Path to nginx config template",
    )
    parser.add_argument(
        "--output",
        default="/etc/nginx/nginx.conf",
        help="Path to generated nginx.conf",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_path(path: str) -> str:
    if path == "/":
        return path
    return path.rstrip("/")


def load_routes(path: Path) -> list[dict]:
    if not path.exists():
        fail(f"routes file not found: {path}")

    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        fail(f"invalid YAML in {path}: {exc}")

    if not isinstance(raw, dict):
        fail("routes config must be a mapping with key 'domains'")

    domains = raw.get("domains")
    if not isinstance(domains, list) or not domains:
        fail("'domains' must be a non-empty list")

    seen_pairs: set[tuple[str, str]] = set()
    normalized_domains: list[dict] = []

    for domain_index, domain in enumerate(domains, start=1):
        if not isinstance(domain, dict):
            fail(f"domain entry #{domain_index} must be a mapping")

        host = domain.get("host")
        if not isinstance(host, str) or not host.strip():
            fail(f"domain entry #{domain_index} has empty or invalid 'host'")
        host = host.strip()

        routes = domain.get("routes")
        if not isinstance(routes, list) or not routes:
            fail(f"domain '{host}' must have a non-empty 'routes' list")

        normalized_routes: list[dict] = []

        for route_index, route in enumerate(routes, start=1):
            if not isinstance(route, dict):
                fail(f"route #{route_index} for host '{host}' must be a mapping")

            path_value = route.get("path")
            if not isinstance(path_value, str) or not path_value:
                fail(f"route #{route_index} for host '{host}' has invalid 'path'")
            if not path_value.startswith("/"):
                fail(f"path '{path_value}' for host '{host}' must start with '/'")

            upstream = route.get("upstream")
            if not isinstance(upstream, str) or not upstream:
                fail(f"route '{host} {path_value}' has invalid 'upstream'")
            if not (upstream.startswith("http://") or upstream.startswith("https://")):
                fail(
                    f"upstream '{upstream}' for host '{host}' must start with "
                    "'http://' or 'https://'"
                )

            normalized_path = normalize_path(path_value)
            key = (host, normalized_path)
            if key in seen_pairs:
                fail(f"duplicate route detected for host '{host}' and path '{normalized_path}'")
            seen_pairs.add(key)

            normalized_routes.append(
                {
                    "path": normalized_path,
                    "upstream": upstream,
                }
            )

        normalized_routes.sort(key=lambda item: len(item["path"]), reverse=True)
        normalized_domains.append({"host": host, "routes": normalized_routes})

    return normalized_domains


def render_proxy_headers(indent: str = " " * 12) -> str:
    directives = [
        "proxy_http_version 1.1;",
        "proxy_set_header Host $host;",
        "proxy_set_header X-Real-IP $remote_addr;",
        "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
        "proxy_set_header X-Forwarded-Proto $scheme;",
        "proxy_set_header Upgrade $http_upgrade;",
        "proxy_set_header Connection $connection_upgrade;",
        "proxy_connect_timeout 5s;",
        "proxy_send_timeout 60s;",
        "proxy_read_timeout 60s;",
        "send_timeout 60s;",
        "proxy_buffering off;",
    ]
    return "\n".join(f"{indent}{directive}" for directive in directives)


def render_route_locations(routes: list[dict]) -> str:
    blocks: list[str] = []
    headers = render_proxy_headers()

    for route in routes:
        path = route["path"]
        upstream = route["upstream"]

        if path == "/":
            block = f"""\
        location / {{
            set $gateway_upstream {upstream};
{headers}
            proxy_pass $gateway_upstream;
        }}"""
        else:
            block = f"""\
        location = {path} {{
            set $gateway_upstream {upstream};
            rewrite ^ {"/"} break;
{headers}
            proxy_pass $gateway_upstream;
        }}

        location = {path}/ {{
            set $gateway_upstream {upstream};
            rewrite ^ {"/"} break;
{headers}
            proxy_pass $gateway_upstream;
        }}

        location ^~ {path}/ {{
            set $gateway_upstream {upstream};
            rewrite ^{path}(/.*)$ $1 break;
{headers}
            proxy_pass $gateway_upstream;
        }}"""

        blocks.append(block)

    blocks.append(
        """\
        location / {
            return 404;
        }"""
    )
    return "\n\n".join(blocks)


def render_http_server(host: str) -> str:
    return f"""\
    server {{
        listen 80;
        listen [::]:80;
        server_name {host};

        location ^~ /.well-known/acme-challenge/ {{
            root /var/www/certbot;
            try_files $uri =404;
        }}

        location / {{
            return 301 https://$host$request_uri;
        }}
    }}"""


def resolve_certificate_paths(host: str) -> tuple[str, str]:
    fullchain = Path(f"/etc/letsencrypt/live/{host}/fullchain.pem")
    privkey = Path(f"/etc/letsencrypt/live/{host}/privkey.pem")

    if fullchain.exists() and privkey.exists():
        return str(fullchain), str(privkey)

    print(
        f"WARNING: certificate for '{host}' not found, using fallback self-signed cert",
        file=sys.stderr,
    )
    return "/etc/nginx/fallback/default.crt", "/etc/nginx/fallback/default.key"


def render_https_server(host: str, routes: list[dict]) -> str:
    route_locations = render_route_locations(routes)
    ssl_certificate, ssl_certificate_key = resolve_certificate_paths(host)
    return f"""\
    server {{
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name {host};

        ssl_certificate {ssl_certificate};
        ssl_certificate_key {ssl_certificate_key};

{route_locations}
    }}"""


def render_domain_servers(domains: list[dict]) -> str:
    servers: list[str] = []
    for domain in domains:
        host = domain["host"]
        routes = domain["routes"]
        servers.append(render_http_server(host))
        servers.append(render_https_server(host, routes))
    return "\n\n".join(servers)


def generate_config(template_path: Path, domains: list[dict]) -> str:
    if not template_path.exists():
        fail(f"template file not found: {template_path}")

    template = template_path.read_text(encoding="utf-8")
    return template.replace("${SERVER_BLOCKS}", render_domain_servers(domains))


def main() -> None:
    args = parse_args()
    routes_path = Path(args.routes)
    template_path = Path(args.template)
    output_path = Path(args.output)

    domains = load_routes(routes_path)
    rendered = generate_config(template_path, domains)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8")
    print(f"Generated nginx config: {output_path}")


if __name__ == "__main__":
    main()
