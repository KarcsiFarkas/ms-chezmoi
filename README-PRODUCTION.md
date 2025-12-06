# PaaS Production Stack - Chezmoi Configuration

Multi-OS dotfiles and **Production PaaS Stack** deployment system using Chezmoi.

---

## 🎯 What's New: Production Profile

This repository now includes a **full production PaaS stack** with 15+ self-hosted services, all managed through Chezmoi templates.

### Key Features

✅ **Conditional Service Deployment** - Only enabled services are included in generated files
✅ **Environment-Driven Configuration** - Configure everything via environment variables
✅ **Production-Ready** - PostgreSQL, LLDAP, Authelia, Traefik pre-configured
✅ **Security First** - Automatic secret generation, secure defaults
✅ **Git-Tracked Templates** - All services in git, only enabled ones deployed
✅ **Clean Installs** - Tested on fresh Ubuntu/WSL systems

---

## 📦 Available Deployment Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| **minimal** | Basic services (Traefik, Vaultwarden, Homepage, Gitea) | Development, testing |
| **production** | Full PaaS stack with SSO, databases, optional services | Production deployments |

---

## 🚀 Quick Start (Production)

```bash
# 1. Install prerequisites
sudo apt update
sudo apt install -y docker.io docker-compose-plugin chezmoi git

# 2. Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# 3. Clone repository
git clone /path/to/ms-chezmoi ~/.local/share/chezmoi
cd ~/.local/share/chezmoi

# 4. Copy and configure
cp production-config.env.example ~/.paas-config.env
nano ~/.paas-config.env  # Edit configuration

# 5. Deploy
source ~/.paas-config.env
chezmoi init
chezmoi apply -v

# 6. Verify
cd ~/opt/docker/production
docker ps
```

**📖 Full Guide:** See [DEPLOYMENT.md](./DEPLOYMENT.md) for complete instructions.

---

## 🏗️ Repository Structure

```
ms-chezmoi/
├── opt/docker/
│   ├── production/              # Production PaaS stack templates
│   │   ├── docker-compose.yml.tmpl
│   │   ├── dot_env.tmpl
│   │   ├── authelia/
│   │   │   └── configuration.yml.tmpl
│   │   ├── postgres/
│   │   │   └── init-multiple-databases.sh.tmpl
│   │   └── traefik/
│   │       └── dynamic/.gitkeep
│   │
│   └── minimal/                 # Minimal deployment templates
│       ├── docker-compose.yml.tmpl
│       └── dot_env.tmpl
│
├── home/
│   ├── .chezmoiscripts/         # Deployment automation scripts
│   │   ├── run_onchange_before_create-docker-network.sh.tmpl
│   │   └── run_after_deploy-docker-stack.sh.tmpl
│   ├── .config/                 # Dotfiles configuration
│   ├── dot_bashrc.tmpl
│   └── dot_zshrc.tmpl
│
├── scripts/                     # Post-deployment scripts
│   └── post-ansible-deploy.sh
│
├── .chezmoidata.yaml.tmpl       # Main configuration template
├── production-config.env.example # Example configuration
├── DEPLOYMENT.md                # Comprehensive deployment guide
└── README.md                    # General dotfiles guide
```

---

## 📋 Available Services

### Core Infrastructure (Always Deployed)

| Service | Purpose | URL |
|---------|---------|-----|
| **Traefik** | Reverse proxy, automatic HTTPS | `http://localhost:8080` |

### Authentication (Enabled by Default)

| Service | Purpose | URL |
|---------|---------|-----|
| **PostgreSQL** | Multi-database server | Internal only |
| **LLDAP** | Lightweight LDAP directory | `ldap.{domain}` |
| **Authelia** | SSO with 2FA support | `auth.{domain}` |
| **Vaultwarden** | Password manager (Bitwarden) | `vault.{domain}` |
| **Homepage** | Service dashboard | `{domain}` |

### Optional Services (Enable via Config)

| Service | Enable Variable | URL Pattern |
|---------|----------------|-------------|
| **Nextcloud** | `ENABLE_NEXTCLOUD=true` | `nextcloud.{domain}` |
| **GitLab** | `ENABLE_GITLAB=true` | `gitlab.{domain}` |
| **Gitea** | `ENABLE_GITEA=true` | `gitea.{domain}` |
| **Jellyfin** | `ENABLE_JELLYFIN=true` | `jellyfin.{domain}` |
| **Immich** | `ENABLE_IMMICH=true` | `immich.{domain}` |
| **Vikunja** | `ENABLE_VIKUNJA=true` | `tasks.{domain}` |
| **Stirling PDF** | `ENABLE_STIRLING_PDF=true` | `pdf.{domain}` |

---

## 🔧 Configuration System

### How It Works

1. **Template Files** (`.tmpl`) in git contain ALL services
2. **Environment Variables** control which services to enable
3. **Chezmoi** generates final files with ONLY enabled services
4. **Deployment Scripts** start only the enabled containers

### Example Configuration

```bash
# ~/.paas-config.env
export DEPLOYMENT_PROFILE="production"
export TENANT_DOMAIN="paas.local"

# Enable core services
export ENABLE_POSTGRES="true"
export ENABLE_LLDAP="true"
export ENABLE_AUTHELIA="true"
export ENABLE_VAULTWARDEN="true"

# Enable optional services
export ENABLE_NEXTCLOUD="true"
export ENABLE_JELLYFIN="true"

# Set credentials
export POSTGRES_PASSWORD="$(openssl rand -base64 32)"
export LLDAP_ADMIN_PASSWORD="my_secure_password"
export NEXTCLOUD_ADMIN_PASSWORD="another_secure_password"
```

### Service Selection Impact

**Template File (in git):**
```yaml
# Contains ALL services (Nextcloud, GitLab, Jellyfin, etc.)
services:
  nextcloud:
    ...
  gitlab:
    ...
  jellyfin:
    ...
```

**Generated File (after `chezmoi apply`):**
```yaml
# Only contains ENABLED services
services:
  nextcloud:
    ...
  jellyfin:
    ...
  # GitLab is NOT here because ENABLE_GITLAB was false
```

---

## 🔐 Security Features

### Default Security Measures

✅ **Automatic Secret Generation** - Use `$(openssl rand -base64 32)` in config
✅ **File Permissions** - `.env` files automatically set to `600`
✅ **SSO Integration** - All services can use LLDAP + Authelia
✅ **2FA Support** - Authelia provides TOTP second factor
✅ **Isolated Networks** - Docker services on private `traefik_net`
✅ **HTTPS Ready** - Traefik with Let's Encrypt support

### Recommended Production Hardening

```bash
# 1. Generate strong secrets
export POSTGRES_PASSWORD="$(openssl rand -base64 32)"
export LLDAP_ADMIN_PASSWORD="$(openssl rand -base64 32)"
export AUTHELIA_JWT_SECRET="$(openssl rand -base64 64)"
export AUTHELIA_SESSION_SECRET="$(openssl rand -base64 64)"
export VAULTWARDEN_ADMIN_TOKEN="$(openssl rand -base64 32)"

# 2. Use real domain with Let's Encrypt
export TENANT_DOMAIN="yourdomain.com"
export ACME_EMAIL="admin@yourdomain.com"

# 3. Disable registration after initial setup
export VAULTWARDEN_SIGNUPS_ALLOWED="false"
export GITEA_DISABLE_REGISTRATION="true"
```

---

## 🧪 Testing on Clean Ubuntu

### Prerequisites

- Ubuntu 22.04 or 24.04 (native or WSL)
- 4GB+ RAM (8GB for GitLab)
- 20GB+ free disk space

### Installation Steps

```bash
# 1. System preparation
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-plugin chezmoi git
sudo usermod -aG docker $USER
newgrp docker

# 2. Clone repository
cd ~
git clone /path/to/ms-chezmoi ~/.local/share/chezmoi

# 3. Configure
cd ~/.local/share/chezmoi
cp production-config.env.example ~/.paas-config.env

# Edit configuration (change passwords!)
nano ~/.paas-config.env

# 4. Deploy
source ~/.paas-config.env
chezmoi init
chezmoi apply -v

# 5. Add to /etc/hosts for local testing
sudo tee -a /etc/hosts << EOF
127.0.0.1 paas.local
127.0.0.1 ldap.paas.local
127.0.0.1 auth.paas.local
127.0.0.1 vault.paas.local
EOF

# 6. Access services
firefox https://paas.local
```

---

## 📊 Resource Requirements

| Configuration | RAM | Disk | Services |
|--------------|-----|------|----------|
| **Minimal** | 2GB | 10GB | Traefik, Vaultwarden, Homepage, Gitea |
| **Standard** | 4GB | 20GB | + PostgreSQL, LLDAP, Authelia, Nextcloud |
| **Full** | 8GB | 50GB | + GitLab, Jellyfin, Immich |

---

## 🛠️ Management Commands

```bash
# View generated configuration
chezmoi data

# Re-apply after config changes
source ~/.paas-config.env
chezmoi apply -v

# Check running services
docker ps

# View service logs
docker logs <container_name>

# Restart a service
docker restart <container_name>

# Stop all services
cd ~/opt/docker/production
docker compose down

# Start all services
docker compose up -d
```

---

## 📚 Documentation

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Complete deployment guide with troubleshooting
- **[README.md](./README.md)** - General dotfiles and multi-OS configuration
- **[production-config.env.example](./production-config.env.example)** - Annotated configuration template

---

## 🤝 Contributing

Improvements and bug fixes welcome! Key areas:

- Additional service integrations
- Security enhancements
- Documentation improvements
- Testing on different platforms

---

## 📄 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

- [Chezmoi](https://www.chezmoi.io/) - Dotfile management
- [Traefik](https://traefik.io/) - Modern reverse proxy
- [LLDAP](https://github.com/lldap/lldap) - Lightweight LDAP
- [Authelia](https://www.authelia.com/) - SSO platform
- All open-source service maintainers

---

**Questions?** See [DEPLOYMENT.md](./DEPLOYMENT.md) troubleshooting section or open an issue.
