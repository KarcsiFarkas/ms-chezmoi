# Traefik Configuration

This directory contains Traefik configuration files.

## Structure

```
traefik/
├── dynamic/              # Dynamic configuration (auto-loaded)
│   ├── middlewares.yml   # Reusable middleware definitions
│   └── tls.yml          # TLS security configuration
└── README.md            # This file
```

## Dynamic Configuration

Files in the `dynamic/` directory are automatically loaded by Traefik and can be updated without restarting the container.

### Middlewares

Common middlewares defined in `middlewares.yml`:

- `security-headers`: Adds security headers (HSTS, X-Frame-Options, etc.)
- `compression`: Enables response compression
- `rate-limit`: General rate limiting (100 req/s)
- `rate-limit-strict`: Strict rate limiting (10 req/s)
- `redirect-www`: Redirects www to non-www

### TLS Configuration

TLS options defined in `tls.yml`:

- `default`: TLS 1.2+ with secure cipher suites
- `modern`: TLS 1.3 only (for maximum security)

## Usage

Apply middlewares in docker-compose labels:

```yaml
labels:
  - "traefik.http.routers.myservice.middlewares=security-headers,compression"
```

## Troubleshooting

Check Traefik logs for configuration errors:

```bash
docker compose logs traefik
```

Access the dashboard at: https://traefik.{{ .tenant.domain }}
