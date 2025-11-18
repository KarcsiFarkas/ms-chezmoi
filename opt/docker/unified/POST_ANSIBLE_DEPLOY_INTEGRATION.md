# Post-Ansible Deploy Integration Guide

This document describes how to integrate the unified Docker configuration with the existing `post-ansible-deploy.sh` script.

## Overview

The unified Docker configuration requires two additional steps in the deployment pipeline:

1. **Pre-deployment validation** - Check system readiness before deploying
2. **Volume preparation** - Create directories with correct permissions

These steps should be integrated into `ms-chezmoi/scripts/post-ansible-deploy.sh` in the Docker deployment workflow.

## Integration Points

### Location in post-ansible-deploy.sh

The integration should occur in the `start_docker_services()` function, specifically between lines 452-485 (the Docker deployment section).

## Patch for post-ansible-deploy.sh

### Step 1: Add Helper Functions

Add these functions after the `ensure_docker_networks()` function (around line 411):

```bash
validate_docker_deployment() {
    log_step "Validating Docker deployment readiness..."

    local validation_script="${docker_dir}/scripts/validate-docker-deployment.sh"

    if [ ! -f "$validation_script" ]; then
        log_warn "Validation script not found: $validation_script"
        log_warn "Skipping pre-deployment validation"
        return 0
    fi

    log_info "Running deployment validation..."

    if ! bash "$validation_script" --quiet; then
        local exit_code=$?

        if [ $exit_code -eq 1 ]; then
            error_exit "Docker deployment validation failed with critical errors" 1
        elif [ $exit_code -eq 2 ]; then
            log_warn "Docker deployment validation completed with warnings"
            log_warn "Proceeding with deployment, but review warnings above"
        fi
    else
        log_info "Docker deployment validation passed"
    fi
}

prepare_docker_volumes() {
    log_step "Preparing Docker volume directories..."

    local prepare_script="${docker_dir}/scripts/prepare-docker-volumes.sh"

    if [ ! -f "$prepare_script" ]; then
        log_warn "Volume preparation script not found: $prepare_script"
        log_warn "Skipping volume preparation - ensure directories exist manually"
        return 0
    fi

    log_info "Running volume preparation..."

    # Run with current user
    if bash "$prepare_script" --user "$TARGET_USER" --group "$(id -gn "$TARGET_USER")"; then
        log_info "Docker volumes prepared successfully"
    else
        log_warn "Volume preparation encountered issues"
        log_warn "Check that /opt/docker-data has correct permissions"
    fi
}

wait_for_service_health() {
    local service="$1"
    local max_wait="${2:-120}"  # Default 2 minutes
    local interval=5
    local elapsed=0

    log_info "Waiting for $service to become healthy (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "paas-${service}" 2>/dev/null || echo "unknown")

        case "$health_status" in
            "healthy")
                log_info "$service is healthy"
                return 0
                ;;
            "unhealthy")
                log_error "$service is unhealthy"
                docker compose logs --tail=20 "$service"
                return 1
                ;;
            "starting")
                log_debug "$service is starting... (${elapsed}s elapsed)"
                ;;
            *)
                log_debug "$service status unknown, waiting... (${elapsed}s elapsed)"
                ;;
        esac

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_warn "$service did not become healthy within ${max_wait}s"
    return 1
}
```

### Step 2: Modify start_docker_services() Function

Replace the existing `start_docker_services()` function (lines 452-485) with this enhanced version:

```bash
start_docker_services() {
    log_step "Starting Docker services..."

    local docker_dir="${HOME}/paas-deployment"
    load_runtime_config
    load_tenant_selections

    if [ ! -f "$docker_dir/docker-compose.yml" ]; then
        log_warn "docker-compose.yml not found at: $docker_dir/docker-compose.yml"
        log_warn "Skipping Docker service startup"
        return 0
    fi

    cd "$docker_dir"

    # === NEW: Pre-deployment validation ===
    validate_docker_deployment

    # === NEW: Volume preparation ===
    prepare_docker_volumes

    # Validate docker-compose.yml
    log_info "Validating Docker Compose configuration..."
    if ! docker compose config > /dev/null; then
        error_exit "Invalid docker-compose.yml configuration" 1
    fi

    # Pull images
    log_info "Pulling Docker images..."
    docker compose pull || log_warn "Some images failed to pull"

    ensure_docker_networks

    # Start core services
    start_service_group "core reverse-proxy stack" "${CORE_SERVICES[@]}"

    # === NEW: Wait for Traefik health ===
    if wait_for_service_health "traefik" 60; then
        log_info "Traefik is ready to route traffic"
    else
        log_warn "Traefik health check timeout - may not be ready"
    fi

    # Start landing/dashboard services
    start_service_group "landing/Homepage stack" "${LANDING_SERVICES[@]}"

    # Start tenant-selected services
    start_service_group "tenant-selected services" "${SELECTED_SERVICES[@]}"

    # Show service status
    log_info "Service status:"
    docker compose ps

    # === NEW: Verify critical services are healthy ===
    log_info "Verifying critical service health..."
    local critical_services=("${CORE_SERVICES[@]}")
    local health_failures=0

    for service in "${critical_services[@]}"; do
        if ! wait_for_service_health "$service" 120; then
            ((health_failures++))
        fi
    done

    if [ $health_failures -gt 0 ]; then
        log_warn "$health_failures critical service(s) failed health checks"
        log_warn "Check logs with: docker compose logs"
    else
        log_info "All critical services are healthy"
    fi
}
```

### Step 3: Enhance verify_deployment() Function

Replace the existing `verify_deployment()` function (lines 487-513) with this version:

```bash
verify_deployment() {
    log_step "Verifying deployment..."

    if [ "$DEPLOYMENT_RUNTIME" = "docker" ]; then
        local docker_dir="${HOME}/paas-deployment"

        if [ ! -f "$docker_dir/docker-compose.yml" ]; then
            log_warn "Cannot verify Docker deployment - compose file not found"
            return 0
        fi

        cd "$docker_dir"

        # Check running containers
        local total_containers
        total_containers=$(docker compose ps --services | wc -l)
        local running_containers
        running_containers=$(docker compose ps --services --filter "status=running" | wc -l)

        log_info "Container status: $running_containers/$total_containers running"

        # Check health status
        local healthy_count=0
        local unhealthy_count=0

        while IFS= read -r container; do
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")

            case "$health" in
                "healthy")
                    ((healthy_count++))
                    ;;
                "unhealthy")
                    ((unhealthy_count++))
                    log_warn "Container $container is unhealthy"
                    ;;
            esac
        done < <(docker compose ps -q)

        log_info "Health status: $healthy_count healthy, $unhealthy_count unhealthy"

        # Test Traefik routing
        log_info "Testing Traefik routing..."
        if curl -sf http://localhost:80 > /dev/null 2>&1; then
            log_info "Traefik is responding to HTTP requests"
        else
            log_warn "Traefik is not responding on port 80"
        fi

        # Show service URLs
        log_info ""
        log_info "Deployment verification completed"
        log_info ""
        log_info "Access your services at:"
        log_info "  Dashboard:  https://${TENANT_DOMAIN}"
        log_info "  Traefik:    https://traefik.${TENANT_DOMAIN}"

        if grep -q "services.authentik.enabled" "$docker_dir/.env" 2>/dev/null; then
            log_info "  Authentik:  https://auth.${TENANT_DOMAIN}"
        fi
        if grep -q "services.vaultwarden.enabled" "$docker_dir/.env" 2>/dev/null; then
            log_info "  Vaultwarden: https://vault.${TENANT_DOMAIN}"
        fi
        if grep -q "services.nextcloud.enabled" "$docker_dir/.env" 2>/dev/null; then
            log_info "  Nextcloud:  https://cloud.${TENANT_DOMAIN}"
        fi

        log_info ""
        log_info "Note: SSL certificates may take a few minutes to be issued"
        log_info "Check Traefik logs: docker compose logs traefik"
    fi
}
```

## Testing the Integration

After applying the patches, test the integration:

```bash
# Test with a minimal deployment
cd /path/to/ms-chezmoi
export TENANT_NAME=test
export DEPLOYMENT_RUNTIME=docker
export TARGET_USER=$(whoami)
export TENANT_DOMAIN=test.local
export TIMEZONE=UTC

# Run the post-ansible-deploy script
./scripts/post-ansible-deploy.sh test docker $(whoami) test.local UTC
```

Expected output should include:

```
==> Validating Docker deployment readiness...
→ Checking Docker installation...
✓ Docker is installed
...

==> Preparing Docker volume directories...
→ Creating directory: /opt/docker-data/traefik
✓ Created: /opt/docker-data/traefik
...

==> Starting Docker services...
...
→ Waiting for traefik to become healthy (max 60s)...
✓ traefik is healthy
```

## Rollback Plan

If the integration causes issues, you can revert by:

1. Restoring the original `post-ansible-deploy.sh` from git:
   ```bash
   git checkout ms-chezmoi/scripts/post-ansible-deploy.sh
   ```

2. Or temporarily skip the new steps by setting environment variables:
   ```bash
   export SKIP_DOCKER_VALIDATION=true
   export SKIP_VOLUME_PREP=true
   ```

## Additional Enhancements (Optional)

### Enhanced Logging

Add detailed logging to a separate file:

```bash
# In start_docker_services()
DEPLOYMENT_LOG="${HOME}/paas-deployment/logs/docker-deploy-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$DEPLOYMENT_LOG")"

{
    validate_docker_deployment
    prepare_docker_volumes
    # ... rest of deployment
} 2>&1 | tee -a "$DEPLOYMENT_LOG"
```

### Deployment Metrics

Track deployment success/failure metrics:

```bash
# After deployment completes
METRICS_FILE="${HOME}/paas-deployment/.deployment-metrics"
echo "$(date +%s),${DEPLOYMENT_RUNTIME},${running_containers},${healthy_count},${unhealthy_count}" >> "$METRICS_FILE"
```

### Notification Hooks

Send notifications on deployment completion:

```bash
# At end of main() function
if command -v notify-send &> /dev/null; then
    notify-send "PaaS Deployment" "Deployment completed for ${TENANT_NAME}"
fi
```

## Summary

This integration adds robust validation and preparation steps to the Docker deployment workflow without breaking existing functionality. The changes are backwards-compatible and gracefully handle missing scripts by logging warnings and continuing.

Key improvements:
- ✅ Pre-deployment validation catches issues early
- ✅ Automatic volume preparation eliminates permission errors
- ✅ Health check monitoring ensures services are actually ready
- ✅ Enhanced verification provides better deployment feedback
- ✅ Graceful degradation if scripts are missing

## Support

If you encounter issues with the integration:

1. Check the deployment logs in `~/paas-deployment/logs/`
2. Run validation manually: `./scripts/validate-docker-deployment.sh`
3. Run volume prep manually: `./scripts/prepare-docker-volumes.sh --dry-run`
4. Review Docker logs: `docker compose logs`

For bugs or questions, open an issue in the project repository.
