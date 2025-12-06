# PaaS Docker Unified - Quick Start Guide

**Get your PaaS infrastructure running in 10 minutes**

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Ubuntu 24.04 VM provisioned on Proxmox
- [ ] Domain name configured (e.g., `example.com`)
- [ ] DNS A records pointing to your server IP
- [ ] SSH access to the VM
- [ ] sudo privileges

## Step-by-Step Deployment

### 1. Validate System (2 minutes)

SSH into your VM and run:

```bash
cd /opt/docker/unified
./scripts/validate-docker-deployment.sh
```

**Expected output:**
```
✓ All validations passed!
Your system is ready for Docker deployment.
```

If you see errors, fix them before proceeding.

### 2. Configure Environment (3 minutes)

Create your environment file:

```bash
cp .env.example .env
nano .env
```

**Minimum required changes:**

```bash
# Replace with your actual domain
TENANT_DOMAIN=example.com

# Replace with your email
TRAEFIK_ACME_EMAIL=admin@example.com

# Generate and set these passwords
REDIS_PASSWORD=$(openssl rand -base64 32)
AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32)
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)
VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -base64 48)
```

**Quick password generation:**

```bash
# Generate all passwords at once
echo "REDIS_PASSWORD=$(openssl rand -base64 32)"
echo "AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32)"
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)"
echo "VAULTWARDEN_ADMIN_TOKEN=$(openssl rand -base64 48)"
echo "NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 32)"
echo "NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 32)"
```

Copy these values into your `.env` file.

### 3. Prepare Volumes (1 minute)

Create all required directories:

```bash
./scripts/prepare-docker-volumes.sh
```

**Expected output:**
```
✓ Directory preparation complete
✓ Validation passed
```

### 4. Deploy Services (4 minutes)

Start core services:

```bash
# Start Traefik (reverse proxy)
docker compose --profile core up -d traefik

# Wait for Traefik to be ready
docker compose ps traefik
# Should show: Up (healthy)

# Start all core services
docker compose --profile core up -d
```

**Deploy optional services:**

```bash
# Add Nextcloud (file storage)
docker compose --profile nextcloud up -d

# Add Vaultwarden (password manager)
docker compose --profile vaultwarden up -d

# Add Homepage (dashboard)
docker compose --profile homepage up -d

# Add Immich (photos)
docker compose --profile immich up -d

# Add Jellyfin (media)
docker compose --profile jellyfin up -d

# Add Gitea (git hosting)
docker compose --profile gitea up -d
```

**Or deploy everything at once:**

```bash
docker compose --profile core --profile authentik \
  --profile vaultwarden --profile homepage \
  --profile nextcloud --profile immich \
  --profile jellyfin --profile gitea up -d
```

### 5. Verify Deployment

Check that all services are running:

```bash
docker compose ps
```

**Expected output:**
```
NAME                    STATUS              PORTS
paas-traefik            Up (healthy)        80/tcp, 443/tcp, 8080/tcp
paas-authentik-server   Up (healthy)
paas-redis              Up (healthy)
paas-postgres-authentik Up (healthy)
...
```

All services should show `Up (healthy)`.

## Access Your Services

Open your browser and navigate to:

| Service | URL | Credentials |
|---------|-----|-------------|
| Dashboard | `https://example.com` | N/A (public) |
| Traefik | `https://traefik.example.com` | admin / (from TRAEFIK_DASHBOARD_AUTH) |
| Authentik | `https://auth.example.com` | Setup wizard on first visit |
| Vaultwarden | `https://vault.example.com` | Create account |
| Nextcloud | `https://cloud.example.com` | admin / (from .env) |
| Immich | `https://photos.example.com` | Create account |
| Jellyfin | `https://media.example.com` | Setup wizard |
| Gitea | `https://gitea.example.com` | Setup wizard |

## Initial Service Configuration

### Authentik (SSO)

1. Visit `https://auth.example.com`
2. Complete the setup wizard
3. Create your admin account
4. Configure authentication flows

### Vaultwarden (Passwords)

1. Visit `https://vault.example.com`
2. Create your user account
3. Install browser extension (optional)
4. Access admin panel: `https://vault.example.com/admin`
   - Token from `.env` file (`VAULTWARDEN_ADMIN_TOKEN`)

### Nextcloud (Files)

1. Visit `https://cloud.example.com`
2. Login with admin credentials from `.env`
3. Install recommended apps
4. Create user accounts

### Homepage (Dashboard)

The dashboard should automatically show all your deployed services.

## Troubleshooting

### SSL Certificates Not Working

**Symptom:** Browser shows "Not Secure" warning

**Solution:**
- Wait 2-3 minutes for Let's Encrypt to issue certificates
- Check Traefik logs: `docker compose logs traefik`
- Verify domain DNS is pointing to your server: `dig example.com`
- Ensure ports 80 and 443 are open in firewall

### Service Not Accessible

**Symptom:** Can't reach service at subdomain

**Solution:**
```bash
# Check service is running
docker compose ps [service-name]

# Check service logs
docker compose logs [service-name]

# Check Traefik routing
docker compose logs traefik | grep [service-name]

# Verify network connectivity
docker compose exec traefik ping [service-name]
```

### Permission Errors

**Symptom:** Service logs show "Permission denied"

**Solution:**
```bash
# Re-run volume preparation
./scripts/prepare-docker-volumes.sh

# Or manually fix permissions
sudo chown -R $USER:$USER /opt/docker-data
```

### Out of Memory

**Symptom:** Services keep restarting

**Solution:**
```bash
# Check system resources
free -h
docker stats

# Reduce resource limits in docker-compose.yml
# Or deploy fewer services
```

## Next Steps

### Secure Your Deployment

1. **Enable Authentik SSO** for all services
2. **Configure firewall** (UFW)
3. **Set up fail2ban** for brute-force protection
4. **Enable 2FA** in Authentik
5. **Review security headers** in Traefik

### Set Up Backups

1. **Create backup script** (see README.md)
2. **Schedule daily backups** with cron
3. **Test restore procedure**
4. **Configure offsite backup** storage

### Monitor Your Services

1. **Check logs regularly:** `docker compose logs`
2. **Monitor resource usage:** `docker stats`
3. **Review Traefik dashboard:** `https://traefik.example.com`
4. **Set up uptime monitoring** (optional)

### Add More Services

Browse the service catalog in `docker-compose.yml.tmpl` to see all available services. Enable them by:

1. Adding configuration to `.env`
2. Deploying with profile: `docker compose --profile [service] up -d`

## Common Commands

```bash
# View logs
docker compose logs -f [service]

# Restart service
docker compose restart [service]

# Stop all services
docker compose stop

# Start all services
docker compose start

# Update services
docker compose pull
docker compose up -d

# Remove everything (⚠️  DATA LOSS)
docker compose down -v
```

## Getting Help

- **Documentation**: See `README.md` for comprehensive guide
- **Validation**: Run `./scripts/validate-docker-deployment.sh`
- **Service Logs**: `docker compose logs [service]`
- **Health Status**: `docker compose ps`

## Success Checklist

You're successfully deployed when:

- [ ] All services show `Up (healthy)` in `docker compose ps`
- [ ] You can access the dashboard at your domain
- [ ] SSL certificates are issued (green padlock in browser)
- [ ] You've changed all default passwords
- [ ] You've configured at least one user account
- [ ] You've tested accessing each deployed service
- [ ] Backups are configured

**Congratulations! Your PaaS is ready to use! 🎉**
