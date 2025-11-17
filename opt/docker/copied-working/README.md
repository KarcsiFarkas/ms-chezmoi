# Docker Copied-Working Configuration

This is the **default deployment configuration** for Docker-based PaaS deployments via Chezmoi.

## Purpose

This folder contains a **proven working configuration** copied from `management-system/docker-minimal-manual/` that has been tested and verified to work correctly.

## What's Different from Other Folders?

### opt/docker/minimal/
- **Purpose**: Template/reference for adding new services
- **Status**: Reference only, not deployed by default
- **Use case**: Copy service definitions from here when adding new services

### opt/docker/production/
- **Purpose**: Full production setup with additional services and configs
- **Status**: Not deployed by default
- **Use case**: Advanced deployments with more complex requirements

### opt/docker/copied-working/ (This folder)
- **Purpose**: Default working deployment
- **Status**: **Deployed by default** (minimal and production are ignored)
- **Use case**: Quick, reliable deployment for standard PaaS setup

## Deployment

When you run `chezmoi apply`, this folder will be deployed to `/opt/docker/copied-working/` with:
- `docker-compose.yml` - Generated from template with your tenant configuration
- `.env` - Generated from template with your service credentials

## How to Deploy

From `/opt/docker/copied-working/`:

```bash
# Start all services
docker compose up -d

# Start specific service (recommended for first setup)
docker compose up -d traefik
docker compose up -d vaultwarden
docker compose up -d immich
# ... etc
```

## Services Included

- **Traefik** - Reverse proxy with automatic SSL
- **Authentik** - SSO and identity provider
- **Immich** - Photo management and backup
- **Jellyfin** - Media streaming
- **Gitea** - Git hosting
- **Vaultwarden** - Password manager
- **Nextcloud** - File sync and storage
- **Homepage** - Dashboard

All services are conditionally deployed based on `.services.<service>.enabled` in your Chezmoi configuration.

## Configuration Management

Service configurations are managed in `.chezmoi.yaml.tmpl` under the `data.services` section.

Example:
```yaml
data:
  services:
    vaultwarden:
      enabled: true
      admin_token: "your-secure-token"
      signups_allowed: "true"
```

## Updating Configuration

1. Edit `.chezmoi.yaml.tmpl` or your environment variables
2. Run `chezmoi apply` to regenerate files
3. Restart affected services: `docker compose up -d <service>`

## Troubleshooting

### Services not starting
Check the logs:
```bash
docker compose logs <service-name>
```

### Port conflicts
Ensure no other services are using ports 80, 443, 8080

### SSL certificate errors
Check Traefik logs and ensure:
- Domain is publicly accessible (for Let's Encrypt)
- Email is configured in TRAEFIK_ACME_EMAIL
- For local testing, consider using HTTP-only routing

## Migration from docker-minimal-manual

This configuration was copied from the proven working setup in `management-system/docker-minimal-manual/`.

Key differences:
- Converted to Chezmoi templates
- Integrated with tenant/deployment configuration
- Conditional service deployment based on `.services.<service>.enabled`
- Centralized credential management via Chezmoi data

## Adding New Services

1. Check `opt/docker/minimal/` for service templates
2. Copy service definition to this `docker-compose.yml.tmpl`
3. Add service configuration to `.chezmoi.yaml.tmpl` under `data.services`
4. Add environment variables to `dot_env.tmpl`
5. Run `chezmoi apply` and test
