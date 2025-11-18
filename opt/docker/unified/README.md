# PaaS Docker Unified Configuration

**Production-ready Docker Compose configuration for the PaaS infrastructure automation framework**

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Services](#services)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Management](#management)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Backup & Recovery](#backup--recovery)

## Overview

This unified Docker configuration provides a complete, production-ready Platform-as-a-Service deployment with:

- **Security-first design**: Non-root containers, read-only mounts, resource limits
- **Automated SSL**: Let's Encrypt integration via Traefik
- **Service isolation**: Separate frontend and backend networks
- **Health monitoring**: Comprehensive health checks for all services
- **Observable**: JSON logging, Prometheus metrics
- **Scalable**: Profile-based service activation

### Design Philosophy

1. **Security**: All containers run as non-root users, security options enabled
2. **Reliability**: Health checks, restart policies, graceful shutdown
3. **Performance**: Resource limits, caching strategies, optimized images
4. **Maintainability**: Clear structure, extensive documentation, modular design

## Architecture

### Network Topology

```
Internet
    |
    v
[Traefik] --- HTTPS/SSL Termination
    |
    +--- paas_frontend (172.20.0.0/24)
    |        |
    |        +--- Authentik (SSO)
    |        +--- Vaultwarden (Passwords)
    |        +--- Homepage (Dashboard)
    |        +--- Nextcloud (Files)
    |        +--- Immich (Photos)
    |        +--- Jellyfin (Media)
    |        +--- Gitea (Git)
    |
    +--- paas_backend (172.21.0.0/24)
             |
             +--- PostgreSQL (Databases)
             +--- Redis (Cache)
```

### Directory Structure

```
unified/
├── docker-compose.yml.tmpl    # Main compose file (Chezmoi template)
├── .env.example              # Environment variable template
├── README.md                 # This file
├── configs/                  # Service-specific configurations
│   ├── traefik/
│   │   ├── dynamic/         # Auto-loaded Traefik config
│   │   │   ├── middlewares.yml.tmpl
│   │   │   └── tls.yml.tmpl
│   │   └── README.md
│   ├── homepage/
│   │   ├── services.yaml.tmpl
│   │   ├── settings.yaml.tmpl
│   │   └── widgets.yaml.tmpl
│   ├── authentik/
│   ├── vaultwarden/
│   └── [other services]/
└── scripts/
    ├── prepare-docker-volumes.sh       # Volume preparation
    └── validate-docker-deployment.sh   # Pre-deployment validation
```

## Prerequisites

### System Requirements

- **OS**: Ubuntu 24.04 LTS or compatible Linux distribution
- **CPU**: Minimum 2 cores, recommended 4+ cores
- **RAM**: Minimum 4GB, recommended 8GB+ for multiple services
- **Disk**: Minimum 20GB free, recommended 100GB+ for media services
- **Network**: Public domain with DNS configured

### Software Requirements

- **Docker**: Version 24.0 or higher
- **Docker Compose**: v2 plugin (not standalone v1)
- **Chezmoi**: For template rendering (if deploying via automation)
- **OpenSSL**: For generating credentials

### Domain & DNS

- Valid domain name (e.g., `example.com`)
- DNS A records pointing to your server:
  - `example.com` → Server IP
  - `*.example.com` → Server IP (wildcard)

### Port Requirements

The following ports must be available:

- **80/TCP**: HTTP (redirects to HTTPS)
- **443/TCP**: HTTPS
- **8080/TCP**: Traefik dashboard
- **2222/TCP**: Gitea SSH (optional)

## Quick Start

### 1. Validate System

Run the validation script to ensure your system meets all requirements:

```bash
cd /path/to/unified
./scripts/validate-docker-deployment.sh
```

Fix any errors before proceeding.

### 2. Configure Environment

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
```

**Required variables:**

```bash
# Core configuration
TENANT_DOMAIN=example.com
TRAEFIK_ACME_EMAIL=admin@example.com

# Generate with: openssl rand -base64 32
REDIS_PASSWORD=your-secure-password-here

# For each enabled service, generate unique passwords
AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32)
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)
VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -base64 48)
# ... etc
```

See [Configuration](#configuration) section for complete details.

### 3. Prepare Volumes

Create all required directories with correct permissions:

```bash
./scripts/prepare-docker-volumes.sh
```

This script will:
- Create `/opt/docker-data` structure
- Set correct ownership and permissions
- Validate completion

### 4. Deploy Services

Deploy core services first:

```bash
# Deploy Traefik (reverse proxy)
docker compose --profile core up -d traefik

# Wait for Traefik to be healthy
docker compose ps traefik

# Deploy remaining core services
docker compose --profile core up -d
```

Deploy optional services as needed:

```bash
# Deploy Nextcloud
docker compose --profile nextcloud up -d

# Deploy Immich (photos)
docker compose --profile immich up -d

# Deploy Jellyfin (media)
docker compose --profile jellyfin up -d

# Deploy Gitea (git)
docker compose --profile gitea up -d
```

### 5. Verify Deployment

Check that all services are healthy:

```bash
docker compose ps
```

All services should show status "Up" with "(healthy)" indicator.

Access your services:

- Dashboard: `https://your-domain.com`
- Traefik: `https://traefik.your-domain.com`
- Services: `https://[service].your-domain.com`

## Services

### Core Services (Always Deployed)

#### Traefik
- **Purpose**: Reverse proxy, SSL termination, automatic service discovery
- **URL**: `https://traefik.{domain}`
- **Dashboard Auth**: Set in `TRAEFIK_DASHBOARD_AUTH`
- **Profile**: `core`

#### PostgreSQL
- **Purpose**: Database backend for Authentik, Nextcloud, Immich
- **Ports**: Internal only (5432)
- **Profiles**: `core`, `authentik`, `nextcloud`, `immich`

#### Redis
- **Purpose**: Cache and session storage
- **Ports**: Internal only (6379)
- **Profile**: `core`

### Authentication & SSO

#### Authentik
- **Purpose**: Identity provider, SSO, 2FA
- **URL**: `https://auth.{domain}`
- **Profile**: `authentik` (enabled by default)
- **Resources**: 2 CPU, 2GB RAM

### Password Management

#### Vaultwarden
- **Purpose**: Self-hosted password manager (Bitwarden-compatible)
- **URL**: `https://vault.{domain}`
- **Admin Panel**: `https://vault.{domain}/admin`
- **Profile**: `vaultwarden`
- **Resources**: 1 CPU, 512MB RAM

### Dashboard

#### Homepage
- **Purpose**: Unified dashboard for all services
- **URL**: `https://{domain}` and `https://home.{domain}`
- **Profile**: `homepage`
- **Resources**: 0.5 CPU, 512MB RAM

### File Storage & Collaboration

#### Nextcloud
- **Purpose**: File storage, sharing, calendars, contacts
- **URL**: `https://cloud.{domain}`
- **Profile**: `nextcloud`
- **Resources**: 4 CPU, 4GB RAM
- **Includes**: PostgreSQL database, cron job container

### Photo Management

#### Immich
- **Purpose**: Photo and video backup with ML features
- **URL**: `https://photos.{domain}`
- **Profile**: `immich`
- **Resources**: 4 CPU, 4GB RAM (server), 4 CPU, 4GB RAM (ML)
- **Includes**: PostgreSQL database, ML container

### Media Streaming

#### Jellyfin
- **Purpose**: Media server for movies, TV shows, music
- **URL**: `https://media.{domain}`
- **Profile**: `jellyfin`
- **Resources**: 4 CPU, 4GB RAM
- **Media Paths**: Configure in `.env`

### Code Hosting

#### Gitea
- **Purpose**: Self-hosted Git service
- **URL**: `https://git.{domain}`
- **SSH Port**: 2222
- **Profile**: `gitea`
- **Resources**: 2 CPU, 2GB RAM

## Configuration

### Environment Variables

All configuration is managed through the `.env` file. See `.env.example` for the complete list.

#### Core Configuration

```bash
# Tenant identification
TENANT_NAME=my-paas
TENANT_DOMAIN=example.com

# Deployment settings
DEPLOYMENT_RUNTIME=docker
DEPLOYMENT_TIMEZONE=Europe/London

# Data directory (bind mounts)
DOCKER_DATA_DIR=/opt/docker-data
```

#### Service Selection

Services are enabled/disabled via Docker Compose profiles. Edit your `.env`:

```bash
# Enable services by setting profiles
COMPOSE_PROFILES=core,authentik,vaultwarden,homepage,nextcloud
```

Or specify when deploying:

```bash
docker compose --profile nextcloud up -d
```

#### Credential Generation

Generate secure credentials using OpenSSL:

```bash
# Standard password (32 chars)
openssl rand -base64 32

# Long password (60 chars for Authentik)
openssl rand -base64 60

# Traefik dashboard auth
echo $(htpasswd -nb admin YourPassword) | sed -e s/\\$/\\$\\$/g
```

For Gitea-specific secrets:

```bash
# Generate secret key
docker run --rm gitea/gitea:latest gitea generate secret SECRET_KEY

# Generate internal token
docker run --rm gitea/gitea:latest gitea generate secret INTERNAL_TOKEN
```

#### SMTP Configuration (Optional)

For email notifications (password resets, invitations, etc.):

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=noreply@example.com
SMTP_USE_TLS=true
```

### Service-Specific Configuration

#### Traefik

Edit `configs/traefik/dynamic/middlewares.yml` to customize:
- Security headers
- Rate limiting
- IP whitelisting
- Authentication

#### Homepage

Edit `configs/homepage/*.yaml` to customize:
- Service list and organization
- Theme and colors
- Widgets

#### Authentik

Place custom templates in `${DOCKER_DATA_DIR}/authentik/templates/`

#### Media Directories (Jellyfin)

Create media directories and set permissions:

```bash
sudo mkdir -p /opt/docker-data/jellyfin/media/{movies,tv,music}
sudo chown -R $USER:$USER /opt/docker-data/jellyfin/media
```

Add media files to these directories.

## Deployment

### Deployment Workflow

1. **Validate** → Run validation script
2. **Configure** → Edit `.env` file
3. **Prepare** → Create volume directories
4. **Deploy** → Start services with profiles
5. **Verify** → Check health and access

### Profile-Based Deployment

Use profiles to control which services start:

```bash
# Core services only
docker compose --profile core up -d

# Core + Nextcloud
docker compose --profile core --profile nextcloud up -d

# All services
docker compose --profile core --profile authentik \
  --profile vaultwarden --profile homepage \
  --profile nextcloud --profile immich \
  --profile jellyfin --profile gitea up -d
```

### Initial Service Configuration

After deployment, configure each service:

#### Authentik
1. Access `https://auth.{domain}`
2. Complete initial setup wizard
3. Create admin user
4. Configure authentication flows

#### Vaultwarden
1. Access `https://vault.{domain}`
2. Create user account
3. Access admin panel: `https://vault.{domain}/admin`
4. Configure settings

#### Nextcloud
1. Access `https://cloud.{domain}`
2. Initial setup runs automatically using env vars
3. Install recommended apps
4. Configure external storage (optional)

#### Gitea
1. Access `https://git.{domain}`
2. Complete installation wizard
3. Create admin user
4. Configure SSH access (port 2222)

## Management

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f traefik

# Last 100 lines
docker compose logs --tail=100 authentik-server
```

### Updating Services

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Remove old images
docker image prune -f
```

### Scaling Services

Services with resource limits can be scaled:

```bash
# Scale Authentik workers
docker compose up -d --scale authentik-worker=3
```

### Stopping Services

```bash
# Stop all services
docker compose stop

# Stop specific service
docker compose stop nextcloud

# Stop and remove containers (data preserved)
docker compose down

# Stop and remove everything including volumes (DATA LOSS!)
docker compose down -v  # ⚠️  DESTRUCTIVE
```

### Restarting Services

```bash
# Restart all
docker compose restart

# Restart specific service
docker compose restart traefik
```

## Monitoring

### Health Checks

All services include health checks. View status:

```bash
docker compose ps
```

Services should show "(healthy)" status.

### Traefik Dashboard

Access the Traefik dashboard at `https://traefik.{domain}` to view:
- Active routes and services
- SSL certificate status
- Request metrics
- Middleware chains

### Prometheus Metrics

Traefik exposes Prometheus metrics on port 8081:

```bash
curl http://localhost:8081/metrics
```

### Resource Usage

Monitor resource consumption:

```bash
# Real-time stats
docker stats

# Specific service
docker stats paas-nextcloud
```

## Troubleshooting

### Common Issues

#### Services Not Starting

**Symptom**: Container exits immediately or shows "Restarting"

**Solutions**:
1. Check logs: `docker compose logs [service]`
2. Verify environment variables in `.env`
3. Check file permissions on bind mounts
4. Ensure dependent services are healthy

#### SSL Certificate Issues

**Symptom**: Let's Encrypt certificate not issued

**Solutions**:
1. Verify domain DNS points to server
2. Ensure ports 80/443 are accessible from internet
3. Check Traefik logs: `docker compose logs traefik`
4. Verify `TRAEFIK_ACME_EMAIL` is set
5. For local testing, consider using self-signed certificates

#### Database Connection Errors

**Symptom**: Services can't connect to PostgreSQL/Redis

**Solutions**:
1. Check database health: `docker compose ps postgres-authentik`
2. Verify passwords match in `.env`
3. Ensure services are on same Docker network
4. Check database logs: `docker compose logs postgres-authentik`

#### Permission Denied Errors

**Symptom**: Container can't write to mounted volume

**Solutions**:
1. Re-run volume preparation: `./scripts/prepare-docker-volumes.sh`
2. Check ownership: `ls -la /opt/docker-data/[service]`
3. Fix permissions: `sudo chown -R $USER:$USER /opt/docker-data`

#### Port Conflicts

**Symptom**: "Address already in use" errors

**Solutions**:
1. Check what's using the port: `sudo netstat -tulpn | grep :80`
2. Stop conflicting service
3. Or change port mapping in docker-compose.yml

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Traefik debug logging
# Edit docker-compose.yml, change:
# - "--log.level=INFO"
# to:
# - "--log.level=DEBUG"

# Restart Traefik
docker compose up -d traefik
```

### Accessing Container Shells

For debugging inside containers:

```bash
# Access container shell
docker compose exec traefik sh
docker compose exec nextcloud bash

# Run one-off commands
docker compose exec postgres-authentik psql -U authentik
```

### Health Check Failures

If health checks fail repeatedly:

```bash
# Check health check command manually
docker compose exec [service] /health-check-command

# View recent health check logs
docker inspect paas-[service] | jq '.[0].State.Health'
```

## Security

### Security Best Practices

#### Credential Management

- ✅ **DO**: Use unique passwords for each service
- ✅ **DO**: Generate passwords with sufficient entropy (32+ chars)
- ✅ **DO**: Rotate credentials regularly
- ✅ **DO**: Store `.env` securely (never commit to git)
- ❌ **DON'T**: Use default passwords
- ❌ **DON'T**: Reuse passwords across services

#### Network Security

- All services run in isolated networks
- Backend services (databases) not exposed to frontend network
- Traefik is the only service with public port exposure
- TLS 1.2+ enforced for all HTTPS connections

#### Container Security

- All containers run with `no-new-privileges` security option
- Docker socket mounted read-only where possible
- Resource limits prevent resource exhaustion attacks
- Non-root users wherever possible

#### Regular Maintenance

```bash
# Update all images (monthly)
docker compose pull && docker compose up -d

# Prune unused resources (monthly)
docker system prune -a

# Review logs for suspicious activity (weekly)
docker compose logs --since 7d | grep -i error

# Check for vulnerable images (weekly)
docker scout quickview
```

### Firewall Configuration

Configure UFW to restrict access:

```bash
# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS (for Let's Encrypt and web traffic)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow Gitea SSH (if using)
sudo ufw allow 2222/tcp

# Enable firewall
sudo ufw enable
```

### Fail2ban Integration

Protect against brute-force attacks:

```bash
# Install fail2ban
sudo apt-get install fail2ban

# Create jail for Traefik
sudo nano /etc/fail2ban/jail.d/traefik.conf
```

```ini
[traefik-auth]
enabled = true
filter = traefik-auth
port = http,https
logpath = /opt/docker-data/traefik/access.log
maxretry = 5
bantime = 3600
```

## Backup & Recovery

### What to Backup

#### Critical Data

1. **Docker volumes** (contains all user data)
2. **Configuration files** (`.env`, `configs/`)
3. **SSL certificates** (`/opt/docker-data/traefik/letsencrypt/`)

#### Backup Script

```bash
#!/bin/bash
# backup-paas.sh

BACKUP_DIR="/mnt/backups/paas-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Stop services (optional, for consistent backup)
cd /path/to/unified
docker compose stop

# Backup docker volumes
sudo rsync -a /opt/docker-data/ "$BACKUP_DIR/docker-data/"

# Backup configuration
cp .env "$BACKUP_DIR/"
cp -r configs/ "$BACKUP_DIR/"

# Backup database dumps
docker compose start postgres-authentik
docker compose exec -T postgres-authentik pg_dump -U authentik authentik > "$BACKUP_DIR/authentik.sql"

# Restart services
docker compose start

# Compress backup
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"

echo "Backup completed: $BACKUP_DIR.tar.gz"
```

### Restore Procedure

```bash
# Stop all services
docker compose down

# Restore data directory
sudo rm -rf /opt/docker-data
sudo tar -xzf backup-YYYYMMDD.tar.gz -C /

# Restore configuration
cp backup-YYYYMMDD/.env .
cp -r backup-YYYYMMDD/configs/* configs/

# Start services
docker compose up -d

# Restore databases (if needed)
docker compose exec -T postgres-authentik psql -U authentik < backup-YYYYMMDD/authentik.sql
```

### Automated Backups

Use systemd timer or cron:

```bash
# Cron (daily at 2 AM)
0 2 * * * /path/to/backup-paas.sh >> /var/log/paas-backup.log 2>&1
```

## Support & Resources

### Documentation

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Authentik Documentation](https://goauthentik.io/docs/)
- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [Nextcloud Admin Manual](https://docs.nextcloud.com/server/stable/admin_manual/)
- [Immich Documentation](https://immich.app/docs)
- [Jellyfin Documentation](https://jellyfin.org/docs/)
- [Gitea Documentation](https://docs.gitea.io/)

### Community

- PaaS Project Issues: [GitHub Issues](https://github.com/your-org/paas/issues)
- Docker Community: [Docker Forums](https://forums.docker.com/)

### License

This configuration is part of the thesis-szakdoga PaaS project.

---

**Generated**: 2025-01-18
**Version**: 1.0.0
**Maintainer**: PaaS Infrastructure Team
