# Production PaaS Stack Deployment Guide

Complete guide for deploying the PaaS stack on a clean Ubuntu system using Chezmoi.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Preparation](#system-preparation)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Service Selection](#service-selection)
6. [Deployment](#deployment)
7. [Post-Deployment](#post-deployment)
8. [Testing](#testing)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

- **OS**: Ubuntu 22.04 LTS or Ubuntu 24.04 LTS (WSL or native)
- **RAM**: Minimum 4GB (8GB+ recommended for production)
- **Disk**: Minimum 20GB free space
- **Network**: Internet connection for pulling Docker images

### Required Software

- Docker Engine
- Docker Compose Plugin (v2)
- Chezmoi
- Git

---

## System Preparation

### Step 1: Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2: Install Docker

```bash
# Install Docker Engine
sudo apt install -y docker.io docker-compose-plugin

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add current user to docker group (to run docker without sudo)
sudo usermod -aG docker $USER

# Apply group changes (or logout and login again)
newgrp docker

# Verify Docker installation
docker --version
docker compose version
```

**Expected Output:**
```
Docker version 24.0.x
Docker Compose version v2.x.x
```

### Step 3: Install Chezmoi

```bash
# Install Chezmoi
sudo apt install -y chezmoi

# Verify installation
chezmoi --version
```

**Expected Output:**
```
chezmoi version 2.x.x
```

### Step 4: Install Git

```bash
sudo apt install -y git

# Configure Git (optional but recommended)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

---

## Quick Start

### Option 1: Clone and Initialize Locally

```bash
# Navigate to home directory
cd ~

# Clone the repository
git clone /path/to/thesis-szakdoga/ms-chezmoi ~/.local/share/chezmoi

# Initialize Chezmoi
cd ~/.local/share/chezmoi
chezmoi init
```

### Option 2: Initialize from Remote Repository (Future)

```bash
# Once repository is published to Git
chezmoi init --apply https://github.com/yourusername/ms-chezmoi.git
```

---

## Configuration

### Understanding the Configuration System

The deployment is controlled by **environment variables** that configure:

1. **Deployment Profile**: `minimal` or `production`
2. **Domain**: Your base domain (e.g., `example.local`)
3. **Services**: Which services to enable/disable
4. **Credentials**: Database passwords, admin passwords, API tokens

### Configuration Methods

#### Method 1: Environment Variables (Recommended for Automation)

Create a configuration file:

```bash
# Create environment configuration
cat > ~/.paas-config.env << 'EOF'
# Deployment Settings
export DEPLOYMENT_PROFILE="production"
export TENANT_DOMAIN="paas.local"
export TIMEZONE="Europe/Budapest"

# Core Services
export ENABLE_POSTGRES="true"
export ENABLE_LLDAP="true"
export ENABLE_AUTHELIA="true"
export ENABLE_VAULTWARDEN="true"
export ENABLE_HOMEPAGE="true"

# Optional Services
export ENABLE_NEXTCLOUD="false"
export ENABLE_JELLYFIN="false"
export ENABLE_GITLAB="false"
export ENABLE_GITEA="false"

# Database Credentials
export POSTGRES_PASSWORD="your_secure_postgres_password"
export POSTGRES_USER="paas_user"

# LLDAP Credentials
export LLDAP_JWT_SECRET="$(openssl rand -base64 32)"
export LLDAP_ADMIN_PASSWORD="your_lldap_admin_password"

# Authelia Secrets
export AUTHELIA_JWT_SECRET="$(openssl rand -base64 64)"
export AUTHELIA_SESSION_SECRET="$(openssl rand -base64 64)"
export AUTHELIA_STORAGE_KEY="$(openssl rand -base64 32)"

# Vaultwarden
export VAULTWARDEN_ADMIN_TOKEN="$(openssl rand -base64 32)"
export VAULTWARDEN_SIGNUPS_ALLOWED="true"

# Service Passwords (if enabling these services)
# export NEXTCLOUD_ADMIN_PASSWORD="your_nextcloud_password"
# export GITLAB_ROOT_PASSWORD="your_gitlab_password"
EOF

# Load configuration
source ~/.paas-config.env
```

#### Method 2: Interactive Prompts (Default)

If you don't set environment variables, Chezmoi will prompt you for values during initialization.

```bash
# Initialize without environment variables
chezmoi init

# Chezmoi will ask:
# - Domain name
# - Timezone
# - etc.
```

---

## Service Selection

### Default Enabled Services (Minimal Production)

By default, the following services are enabled:

| Service | Purpose | Default Port/URL |
|---------|---------|------------------|
| **Traefik** | Reverse proxy | `:80`, `:443`, `:8080` |
| **PostgreSQL** | Database | Internal only |
| **LLDAP** | LDAP authentication | `ldap.{domain}` |
| **Authelia** | SSO & 2FA | `auth.{domain}` |
| **Vaultwarden** | Password manager | `vault.{domain}` |
| **Homepage** | Dashboard | `{domain}` |

### Optional Services

Enable additional services by setting environment variables:

```bash
# Development Tools
export ENABLE_GITLAB="true"     # Full-featured Git + CI/CD
export ENABLE_GITEA="true"      # Lightweight Git hosting

# File Storage
export ENABLE_NEXTCLOUD="true"  # File sync and collaboration

# Media Services
export ENABLE_JELLYFIN="true"   # Media streaming server
export ENABLE_IMMICH="true"     # Photo management

# Productivity
export ENABLE_VIKUNJA="true"    # Task management
export ENABLE_STIRLING_PDF="true"  # PDF tools
```

**Important Notes:**

- **GitLab** is resource-intensive (requires 4GB+ RAM)
- **Media services** require storage for media files
- **PostgreSQL** is automatically enabled for services that need it
- **Redis** is enabled automatically if needed by Immich

---

## Deployment

### Step 1: Load Configuration

```bash
# Load your configuration file
source ~/.paas-config.env
```

### Step 2: Apply Chezmoi Configuration

```bash
# Apply Chezmoi templates
# This will:
# 1. Generate docker-compose.yml with ONLY enabled services
# 2. Generate .env file with configured credentials
# 3. Generate authelia configuration
# 4. Create deployment scripts

chezmoi apply -v
```

**Expected Output:**
```
diff --git a/home/.chezmoiscripts/run_onchange_before_create-docker-network.sh b/home/.chezmoiscripts/run_onchange_before_create-docker-network.sh
new file mode 100755
index 0000000..abcdefg
--- /dev/null
+++ b/home/.chezmoiscripts/run_onchange_before_create-docker-network.sh
...
🌐 Creating Docker networks...
  ✓ Creating traefik_net network...
  ✅ traefik_net created
✅ Docker networks ready!
```

### Step 3: Verify Generated Files

```bash
# Check deployment directory
ls -la ~/opt/docker/production/

# Should show:
# - docker-compose.yml (generated from template)
# - .env (with your configuration)
# - authelia/configuration.yml
# - postgres/init-multiple-databases.sh
# - traefik/dynamic/
```

### Step 4: Review Generated Docker Compose

```bash
# View generated docker-compose.yml
cat ~/opt/docker/production/docker-compose.yml

# IMPORTANT: Verify that ONLY enabled services are present
# Disabled services should NOT appear in the generated file
```

### Step 5: Start the Stack

The deployment script runs automatically after `chezmoi apply`. To manually deploy:

```bash
# Navigate to deployment directory
cd ~/opt/docker/production/

# Start enabled services
docker compose --profile traefik --profile postgres --profile lldap --profile authelia --profile vaultwarden --profile homepage up -d
```

Or use the auto-generated script that already knows your enabled services:

```bash
# The deployment script was already run by chezmoi apply
# To re-run it manually:
bash ~/home/.chezmoiscripts/run_after_deploy-docker-stack.sh
```

**Expected Output:**
```
════════════════════════════════════════════════════════════════
  🐳 Docker Stack Deployment
════════════════════════════════════════════════════════════════
  Profile: production
  Domain: paas.local
  Directory: /home/user/opt/docker/production
════════════════════════════════════════════════════════════════

🔒 Set .env permissions to 600
📦 Production Profile - Deploying enabled services...

🎯 Enabled profiles: --profile traefik --profile postgres --profile lldap --profile authelia --profile vaultwarden --profile homepage

📥 Pulling Docker images...
[+] Pulling traefik...
[+] Pulling postgres...
...

🚀 Starting services...
[+] Running 7/7
 ✔ Network traefik_net              Created
 ✔ Container postgres               Started
 ✔ Container traefik                Started
 ✔ Container lldap                  Started
 ✔ Container authelia               Started
 ✔ Container vaultwarden            Started
 ✔ Container homepage               Started

════════════════════════════════════════════════════════════════
  ✅ Production Stack Deployed Successfully!
════════════════════════════════════════════════════════════════

📊 Service URLs:
  • Traefik Dashboard: http://localhost:8080
  • LLDAP: https://ldap.paas.local
  • Authelia: https://auth.paas.local
  • Vaultwarden: https://vault.paas.local
  • Homepage: https://paas.local
```

---

## Post-Deployment

### Step 1: Configure /etc/hosts

For local testing, add domain entries to `/etc/hosts`:

```bash
sudo tee -a /etc/hosts > /dev/null << EOF
# PaaS Stack Services
127.0.0.1 paas.local
127.0.0.1 traefik.paas.local
127.0.0.1 ldap.paas.local
127.0.0.1 auth.paas.local
127.0.0.1 vault.paas.local
127.0.0.1 nextcloud.paas.local
127.0.0.1 gitlab.paas.local
127.0.0.1 jellyfin.paas.local
EOF
```

### Step 2: Verify Container Status

```bash
# Check all running containers
docker ps

# Check container logs
docker logs traefik
docker logs lldap
docker logs authelia
docker logs vaultwarden
```

### Step 3: Access Services

Open your browser and navigate to:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| **Traefik Dashboard** | http://localhost:8080 | No auth (dev mode) |
| **LLDAP** | https://ldap.paas.local | `admin` / your LLDAP_ADMIN_PASSWORD |
| **Authelia** | https://auth.paas.local | Via LLDAP |
| **Vaultwarden** | https://vault.paas.local | Create account |
| **Homepage** | https://paas.local | No auth |

### Step 4: Create LLDAP Users

1. Access LLDAP: https://ldap.paas.local
2. Login with admin credentials
3. Create users:
   - Click "Create User"
   - Fill in: username, email, password
   - Add to groups if needed

### Step 5: Configure Authelia (Optional)

Authelia is pre-configured to use LLDAP. Test authentication:

1. Access any protected service
2. You'll be redirected to Authelia
3. Login with LLDAP credentials
4. Set up 2FA (TOTP) if desired

---

## Testing

### Test 1: Network Connectivity

```bash
# Test Traefik is routing
curl -k https://paas.local

# Should return homepage HTML
```

### Test 2: Service Health

```bash
# Check health of all services
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# All containers should show "Up" status
```

### Test 3: LLDAP Authentication

```bash
# Test LDAP connection
ldapsearch -x -H ldap://localhost:3890 -D "cn=admin,ou=people,dc=paas,dc=local" -w "your_lldap_password" -b "dc=paas,dc=local"

# Should return LDAP directory structure
```

### Test 4: Database Connectivity

```bash
# List PostgreSQL databases
docker exec postgres psql -U paas_user -d paas_db -c "\l"

# Should show all created databases
```

---

## Troubleshooting

### Problem: Containers Not Starting

**Check logs:**
```bash
docker logs <container_name>
```

**Common causes:**
- Port conflicts (check with `sudo netstat -tlnp | grep :80`)
- Incorrect environment variables in `.env`
- Insufficient system resources

**Solution:**
```bash
# Stop all containers
docker compose down

# Check for port conflicts
sudo lsof -i :80
sudo lsof -i :443

# Restart
docker compose up -d
```

### Problem: Cannot Access Services via Domain

**Check /etc/hosts:**
```bash
cat /etc/hosts | grep paas.local
```

**Check Traefik routing:**
```bash
# Access Traefik dashboard
http://localhost:8080

# Look for configured routers and services
```

**Solution:**
```bash
# Ensure entries exist in /etc/hosts
# Or use localhost:PORT directly for testing
```

### Problem: Database Connection Errors

**Check PostgreSQL is running:**
```bash
docker logs postgres
```

**Check database was created:**
```bash
docker exec postgres psql -U paas_user -d postgres -c "\l"
```

**Solution:**
```bash
# Recreate containers (will run init script again)
docker compose down -v
docker compose up -d
```

### Problem: Authelia Not Redirecting

**Check Authelia configuration:**
```bash
cat ~/opt/docker/production/authelia/configuration.yml
```

**Verify LLDAP is running:**
```bash
docker logs lldap
```

**Solution:**
```bash
# Check Authelia logs for errors
docker logs authelia

# Restart Authelia
docker restart authelia
```

### Problem: "Permission Denied" Errors

**Check file permissions:**
```bash
ls -la ~/opt/docker/production/.env
```

**Should be 600 (rw-------):**
```bash
chmod 600 ~/opt/docker/production/.env
```

### Problem: Chezmoi Apply Fails

**Check Chezmoi data:**
```bash
chezmoi data
```

**Verify environment variables:**
```bash
env | grep ENABLE_
env | grep TENANT_
```

**Solution:**
```bash
# Re-source configuration
source ~/.paas-config.env

# Re-apply
chezmoi apply -v
```

---

## Advanced Operations

### Adding New Services

1. **Update configuration:**
   ```bash
   # Edit ~/.paas-config.env
   echo 'export ENABLE_NEXTCLOUD="true"' >> ~/.paas-config.env
   echo 'export NEXTCLOUD_ADMIN_PASSWORD="secure_password"' >> ~/.paas-config.env

   # Reload
   source ~/.paas-config.env
   ```

2. **Re-apply Chezmoi:**
   ```bash
   chezmoi apply -v
   ```

3. **Service will auto-deploy** via the deployment script

### Updating Services

```bash
# Navigate to deployment directory
cd ~/opt/docker/production/

# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d
```

### Backing Up Data

```bash
# Backup Docker volumes
docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz -C /data .

# Backup .env file
cp ~/opt/docker/production/.env ~/opt/docker/production/.env.backup
```

### Removing the Stack

```bash
# Stop and remove all containers
cd ~/opt/docker/production/
docker compose down

# Remove volumes (WARNING: deletes all data)
docker compose down -v
```

---

## Security Considerations

### Production Recommendations

1. **Change All Default Passwords:**
   - Never use `changeme` passwords in production
   - Use `openssl rand -base64 32` for strong secrets

2. **Use Real TLS Certificates:**
   - Configure Let's Encrypt with a real domain
   - Update `ACME_EMAIL` to your email

3. **Restrict Traefik Dashboard:**
   - Set `--api.insecure=false` in production
   - Protect dashboard with Authelia

4. **Enable Firewall:**
   ```bash
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

5. **Regular Updates:**
   ```bash
   # Update Docker images weekly
   docker compose pull
   docker compose up -d
   ```

---

## Summary

**You have successfully deployed a production PaaS stack with:**

✅ Traefik reverse proxy with automatic HTTPS
✅ PostgreSQL multi-database setup
✅ LLDAP for centralized authentication
✅ Authelia for SSO and 2FA
✅ Vaultwarden password manager
✅ Homepage dashboard
✅ Optional services (Nextcloud, GitLab, Jellyfin, etc.)

**All configured via Chezmoi templates** with environment-driven service selection!

---

## Quick Reference Commands

```bash
# View all running containers
docker ps

# Check service logs
docker logs <container_name>

# Restart a service
docker restart <container_name>

# Stop all services
cd ~/opt/docker/production && docker compose down

# Start all services
cd ~/opt/docker/production && docker compose up -d

# Update Chezmoi configuration
source ~/.paas-config.env && chezmoi apply -v

# View generated configuration
chezmoi data
```

---

**Questions or issues?** Check the troubleshooting section or review container logs.
