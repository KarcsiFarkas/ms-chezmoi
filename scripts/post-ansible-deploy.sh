#!/usr/bin/env bash
# ============================================================================
# Post-Ansible Deployment Script
# ============================================================================
# This script is called by Ansible after provisioning completes
# It initializes Chezmoi and deploys all configurations
#
# Usage:
#   ./post-ansible-deploy.sh <tenant_name> <deployment_runtime> <target_user>
#
# Example:
#   ./post-ansible-deploy.sh test docker paasuser
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHEZMOI_SOURCE_DIR="${SCRIPT_DIR}/.."
LOG_DIR="${HOME}/paas-deployment/logs"
LOG_FILE="${LOG_DIR}/post-ansible-deploy-$(date +%Y%m%d-%H%M%S).log"
TENANT_CONFIG_DIR=""
RUNTIME_CONFIG_FILE="/etc/paas/docker-runtime.yaml"

CORE_SERVICES=(traefik authentik vaultwarden)
LANDING_SERVICES=(homepage)
SELECTED_SERVICES=()
DOCKER_NETWORKS=()

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
}

log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [INFO] $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [WARN] $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [ERROR] $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [SUCCESS] $*"
}

log_step() {
    echo -e "\n${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${BLUE}==>${NC} $*\n"
}

# ============================================================================
# Error Handling
# ============================================================================

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_error "Check log file: $LOG_FILE"
    fi
}

trap cleanup EXIT

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# ============================================================================
# Validation
# ============================================================================

validate_arguments() {
    if [ $# -lt 3 ]; then
        error_exit "Usage: $0 <tenant_name> <deployment_runtime> <target_user>" 1
    fi

    TENANT_NAME="$1"
    DEPLOYMENT_RUNTIME="$2"
    TARGET_USER="$3"
    TENANT_DOMAIN="${4:-localhost}"
    TIMEZONE="${5:-UTC}"
    TENANT_CONFIG_DIR="/tmp/chezmoi-${TENANT_NAME}/tenant-config"
    export TENANT_CONFIG_DIR

    log_info "Deployment Parameters:"
    log_info "  Tenant: $TENANT_NAME"
    log_info "  Runtime: $DEPLOYMENT_RUNTIME"
    log_info "  User: $TARGET_USER"
    log_info "  Domain: $TENANT_DOMAIN"
    log_info "  Timezone: $TIMEZONE"

    # Validate runtime
    if [[ ! "$DEPLOYMENT_RUNTIME" =~ ^(docker|nix)$ ]]; then
        error_exit "Invalid deployment runtime: $DEPLOYMENT_RUNTIME (must be 'docker' or 'nix')" 1
    fi
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check if running as target user
    if [ "$(whoami)" != "$TARGET_USER" ]; then
        error_exit "This script must be run as user: $TARGET_USER" 1
    fi

    # Check if Chezmoi is installed
    if ! command -v chezmoi &> /dev/null; then
        log_warn "Chezmoi not found, installing..."
        install_chezmoi
    else
        log_info "Chezmoi is installed: $(chezmoi --version)"
    fi

    local required_tools=(git jq yq python3 rsync tar)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool '$tool' is missing. Install it before continuing." 1
        fi
    done

    if ! python3 - <<'PY' >/dev/null 2>&1
import yaml  # noqa: F401
PY
    then
        error_exit "python3-yaml is required but not available" 1
    fi

    # Runtime-specific checks
    if [ "$DEPLOYMENT_RUNTIME" = "docker" ]; then
        if ! command -v docker &> /dev/null; then
            error_exit "Docker is not installed" 1
        fi
        log_info "Docker version: $(docker --version)"

        if ! docker compose version &> /dev/null; then
            error_exit "Docker Compose v2 plugin is required but missing" 1
        fi

        # Check if user is in docker group
        if ! groups | grep -qw docker; then
            log_warn "User $TARGET_USER is not in docker group"
            log_warn "You may need to run: sudo usermod -aG docker $TARGET_USER"
        fi
    fi
}

install_chezmoi() {
    log_info "Installing Chezmoi..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y chezmoi
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm chezmoi
    else
        # Use binary install method
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if ! command -v chezmoi &> /dev/null; then
        error_exit "Failed to install Chezmoi" 1
    fi

    log_info "Chezmoi installed successfully: $(chezmoi --version)"
}

# ============================================================================
# Chezmoi Configuration
# ============================================================================

export_tenant_env_vars() {
    log_step "Exporting tenant environment variables..."

    if [ ! -f "${TENANT_CONFIG_DIR}/selection.yml" ]; then
        log_info "No selection.yml found, skipping env var export"
        return 0
    fi

    # Parse selection.yml and export ENABLE_<SERVICE>=true
    local env_out
    if env_out=$(python3 - <<EOF
import yaml
import os
import sys

try:
    path = "${TENANT_CONFIG_DIR}/selection.yml"
    with open(path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}

    services = data.get('services', {})
    import re

    for service, config in services.items():
        if isinstance(config, dict) and config.get('enabled'):
            sanitized = re.sub(r'[^A-Za-z0-9_]', '_', service.upper())
            print(f"export ENABLE_{sanitized}=true")
except Exception as e:
    print(f"echo 'Error parsing selection.yml: {e}'", file=sys.stderr)
    sys.exit(1)
EOF
    ); then
        if [ -n "$env_out" ]; then
            eval "$env_out"
            log_info "Exported service enablement variables from selection.yml"
        fi
    else
        log_warn "Failed to parse selection.yml for env vars"
    fi
}

initialize_chezmoi() {
    log_step "Initializing Chezmoi configuration..."

    # Set Chezmoi source directory
    local chezmoi_dir="${HOME}/.local/share/chezmoi"

    # Remove existing Chezmoi directory if exists
    if [ -d "$chezmoi_dir" ]; then
        log_warn "Removing existing Chezmoi directory: $chezmoi_dir"
        rm -rf "$chezmoi_dir"
    fi

    # Remove existing Chezmoi config to ensure fresh init from template
    if [ -d "${HOME}/.config/chezmoi" ]; then
        rm -rf "${HOME}/.config/chezmoi"
    fi

    # Copy Chezmoi source files
    log_info "Copying Chezmoi source files..."
    mkdir -p "$(dirname "$chezmoi_dir")"
    cp -r "$CHEZMOI_SOURCE_DIR" "$chezmoi_dir"

    # Initialize Chezmoi
    log_info "Initializing Chezmoi..."
    chezmoi init || error_exit "Failed to initialize Chezmoi" 1

    log_info "Chezmoi initialized successfully"
}

prepare_chezmoi_data() {
    log_step "Preparing Chezmoi data file..."

    local data_file="${HOME}/.local/share/chezmoi/.chezmoidata.yaml"
    mkdir -p "$(dirname "$data_file")"
    [ -f "$data_file" ] || echo "{}" > "$data_file"

    # Export tenant configuration as environment variables
    export TENANT_NAME
    export DEPLOYMENT_RUNTIME
    export TENANT_DOMAIN
    export TIMEZONE
    export DEPLOYMENT_USER="$TARGET_USER"
    export DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-web-01}"

    # Load tenant service configuration if available
    if [ -d "$TENANT_CONFIG_DIR" ]; then
        log_info "Loading tenant configuration from: $TENANT_CONFIG_DIR"

        # Parse selection.yml and inject into Chezmoi data
        if [ -f "$TENANT_CONFIG_DIR/selection.yml" ]; then
            log_info "Processing tenant service selections..."

            # Create temporary data file with services
            python3 <<EOF
import yaml
import os
import sys

tenant_dir = os.environ.get('TENANT_CONFIG_DIR')
if not tenant_dir:
    print("TENANT_CONFIG_DIR is not set", file=sys.stderr)
    sys.exit(1)

# Resolve data file path
data_file = os.path.expandvars(os.path.expanduser("$data_file"))

# Load tenant selection
try:
    with open(os.path.join(tenant_dir, 'selection.yml'), 'r', encoding='utf-8') as f:
        selection = yaml.safe_load(f)
except Exception as e:
    print(f"Error loading selection.yml: {e}", file=sys.stderr)
    sys.exit(1)

# Load existing data template
try:
    with open(data_file, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
except Exception as e:
    print(f"Error loading data template: {e}", file=sys.stderr)
    sys.exit(1)

# Merge services into data
data['services'] = selection.get('services', {})

# Write updated data file
try:
    with open(data_file, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    print(f"Successfully updated Chezmoi data with {len(data['services'])} services")
except Exception as e:
    print(f"Error writing data file: {e}", file=sys.stderr)
    sys.exit(1)
EOF
        fi
    else
        log_warn "Tenant configuration directory not found: $TENANT_CONFIG_DIR"
        log_warn "Using default configuration"
    fi

    log_info "Chezmoi data prepared successfully"
}

# ============================================================================
# Docker Helpers
# ============================================================================

load_runtime_config() {
    if [ ! -f "$RUNTIME_CONFIG_FILE" ]; then
        log_warn "Docker runtime config not found at $RUNTIME_CONFIG_FILE, using defaults"
        CORE_SERVICES=(traefik authentik vaultwarden)
        LANDING_SERVICES=(homepage)
        DOCKER_NETWORKS=("traefik_net|bridge|true")
        return 0
    fi

    local runtime_json
    if ! runtime_json=$(python3 - "$RUNTIME_CONFIG_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = {}
if path.exists():
    with path.open("r", encoding="utf-8") as handle:
        import yaml  # noqa: PLC0415
        data = yaml.safe_load(handle) or {}

core = data.get("core_services") or []
landing = data.get("landing_services") or []
networks = data.get("networks") or []

print(json.dumps({"core": core, "landing": landing, "networks": networks}))
PY
    ); then
        log_warn "Failed to parse $RUNTIME_CONFIG_FILE, falling back to defaults"
        CORE_SERVICES=(traefik authentik vaultwarden)
        LANDING_SERVICES=(homepage)
        DOCKER_NETWORKS=("traefik_net|bridge|true")
        return 0
    fi

    mapfile -t CORE_SERVICES < <(echo "$runtime_json" | jq -r '.core[]?' 2>/dev/null || true)
    mapfile -t LANDING_SERVICES < <(echo "$runtime_json" | jq -r '.landing[]?' 2>/dev/null || true)

    if [ ${#CORE_SERVICES[@]} -eq 0 ]; then
        CORE_SERVICES=(traefik authentik vaultwarden)
    fi
    if [ ${#LANDING_SERVICES[@]} -eq 0 ]; then
        LANDING_SERVICES=(homepage)
    fi

    DOCKER_NETWORKS=()
    local network_lines
    network_lines="$(echo "$runtime_json" | jq -r '.networks[]? | "\(.name)|\(.driver // \"bridge\")|\(.attachable // false)"' 2>/dev/null || true)"
    if [ -n "$network_lines" ]; then
        while IFS='|' read -r name driver attachable; do
            [ -z "$name" ] && continue
            DOCKER_NETWORKS+=("$name|$driver|$attachable")
        done <<< "$network_lines"
    else
        DOCKER_NETWORKS=("traefik_net|bridge|true")
    fi
}

load_tenant_selections() {
    SELECTED_SERVICES=()
    local selection_file="${TENANT_CONFIG_DIR}/selection.yml"
    if [ ! -f "$selection_file" ]; then
        log_warn "selection.yml not found in $TENANT_CONFIG_DIR; deploying default services only"
        return 0
    fi

    local enabled_services
    if ! enabled_services=$(python3 - "$selection_file" <<'PY'
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
with path.open("r", encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}

services = data.get("services") or {}
for name, cfg in services.items():
    if isinstance(cfg, dict) and cfg.get("enabled"):
        print(name)
PY
    ); then
        log_warn "Unable to parse service selections, continuing with defaults"
        return 0
    fi

    local skip=" ${CORE_SERVICES[*]} ${LANDING_SERVICES[*]} "
    while IFS= read -r svc; do
        [ -z "$svc" ] && continue
        if [[ " $skip " == *" $svc "* ]]; then
            continue
        fi
        SELECTED_SERVICES+=("$svc")
    done <<< "$enabled_services"

    if [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
        log_info "Tenant requested additional services: ${SELECTED_SERVICES[*]}"
    fi
}

ensure_docker_networks() {
    if [ ${#DOCKER_NETWORKS[@]} -eq 0 ]; then
        return 0
    fi

    for definition in "${DOCKER_NETWORKS[@]}"; do
        IFS='|' read -r net_name net_driver net_attachable <<< "$definition"
        if docker network inspect "$net_name" >/dev/null 2>&1; then
            log_info "Docker network '$net_name' already exists"
            continue
        fi

        log_info "Creating docker network '$net_name' (driver=${net_driver})"
        local cmd=(docker network create --driver "$net_driver")
        if [[ "$net_attachable" =~ ^(1|true|True)$ ]]; then
            cmd+=(--attachable)
        fi
        cmd+=("$net_name")

        if ! "${cmd[@]}"; then
            error_exit "Failed to create docker network '$net_name'" 1
        fi
    done
}

start_service_group() {
    local description="$1"
    shift
    local services=("$@")

    if [ ${#services[@]} -eq 0 ]; then
        log_info "Skipping ${description} (no services requested)"
        return 0
    fi

    log_info "Starting ${description}: ${services[*]}"
    if docker compose up -d "${services[@]}"; then
        log_info "${description} started"
    else
        error_exit "Failed to start ${description}" 1
    fi
}

# ============================================================================
# Deployment
# ============================================================================

load_credentials() {
    log_step "Loading generated credentials..."

    local cred_dir="/tmp/chezmoi-${TENANT_NAME}/credentials"
    local cred_file="${cred_dir}/credentials.env"
    local db_cred_file="${cred_dir}/db-credentials.env"

    if [ ! -d "$cred_dir" ]; then
        log_warn "Credentials directory not found: $cred_dir"
        log_warn "Using default/placeholder credentials (INSECURE!)"
        return 0
    fi

    # Load service credentials (export to make available to chezmoi)
    if [ -f "$cred_file" ]; then
        log_info "Loading service credentials from: $cred_file"
        # Use set -a to auto-export all variables when sourcing
        set -a
        # shellcheck disable=SC1090
        source "$cred_file"
        # Keep set -a enabled so variables remain exported after function returns
        local cred_count=$(grep -c '^[^#]' "$cred_file" || echo 0)
        log_success "Loaded $cred_count credential entries"
    else
        log_warn "Service credentials file not found: $cred_file"
        set -a  # Enable export for remaining variables
    fi

    # Load database credentials (also exported)
    if [ -f "$db_cred_file" ]; then
        log_info "Loading database credentials from: $db_cred_file"
        # set -a is already enabled, so these will be exported too
        # shellcheck disable=SC1090
        source "$db_cred_file"
        local db_cred_count=$(grep -c '^[^#]' "$db_cred_file" || echo 0)
        log_success "Loaded $db_cred_count database credential entries"
    else
        log_warn "Database credentials file not found: $db_cred_file"
    fi

    # Note: We deliberately do NOT call 'set +a' here so variables stay exported

    # Verify critical credentials are loaded
    local missing_creds=()

    # Alias for Postgres naming differences
    if [ -z "${POSTGRES_PASSWORD:-}" ] && [ -n "${POSTGRES_DB_PASSWORD:-}" ]; then
        export POSTGRES_PASSWORD="${POSTGRES_DB_PASSWORD}"
    fi

    if [ -z "${TRAEFIK_PASSWORD:-}" ]; then missing_creds+=("TRAEFIK_PASSWORD"); fi
    if [ -z "${POSTGRES_PASSWORD:-}" ]; then missing_creds+=("POSTGRES_PASSWORD"); fi

    if [ ${#missing_creds[@]} -gt 0 ]; then
        log_warn "Missing credentials: ${missing_creds[*]}"
        log_warn "Deployment may use insecure defaults!"
    else
        log_success "✅ All critical credentials loaded"
    fi
}

apply_chezmoi_configuration() {
    log_step "Applying Chezmoi configurations..."

    # Dry-run first to show what will be applied
    log_info "Performing dry-run to preview changes..."
    chezmoi diff || log_warn "No changes detected or diff failed"

    # Apply configurations
    log_info "Applying Chezmoi configurations..."
    # Prevent run_after_deploy-docker-stack.sh from firing before files exist; docker
    # services are started later in this script.
    export SKIP_CHEZMOI_DOCKER_DEPLOY="${SKIP_CHEZMOI_DOCKER_DEPLOY:-1}"
    log_info "Auto docker deploy via Chezmoi scripts disabled (SKIP_CHEZMOI_DOCKER_DEPLOY=${SKIP_CHEZMOI_DOCKER_DEPLOY})"
    if chezmoi apply --verbose; then
        log_info "Chezmoi configurations applied successfully"
    else
        error_exit "Failed to apply Chezmoi configurations" 1
    fi
}

start_docker_services() {
    log_step "Starting Docker services..."

    local docker_dir="${HOME}/paas-deployment"
    # Prevent Docker Compose from interpolating secrets containing '$'
    export COMPOSE_INTERPOLATION=0
    load_runtime_config
    load_tenant_selections

    if [ ! -f "$docker_dir/docker-compose.yml" ]; then
        local fallback_unified="/opt/docker/unified/docker-compose.yml"
        local fallback_copied="/opt/docker/copied-working/docker-compose.yml"
        local template_path="${HOME}/.local/share/chezmoi/home/paas-deployment/docker-compose.yml.tmpl"

        mkdir -p "$docker_dir"

        if [ -f "$template_path" ]; then
            log_warn "docker-compose.yml not found at: $docker_dir/docker-compose.yml"
            log_warn "Rendering docker-compose.yml from template: $template_path"
            if chezmoi execute-template < "$template_path" > "$docker_dir/docker-compose.yml"; then
                log_info "Rendered docker-compose.yml via chezmoi execute-template"
            else
                log_warn "Failed to render template via chezmoi execute-template"
            fi
        fi

        if [ ! -f "$docker_dir/docker-compose.yml" ] && [ -f "$fallback_unified" ]; then
            log_warn "Using fallback compose from $fallback_unified"
            cp "$fallback_unified" "$docker_dir/docker-compose.yml"
        elif [ ! -f "$docker_dir/docker-compose.yml" ] && [ -f "$fallback_copied" ]; then
            log_warn "Using fallback compose from $fallback_copied"
            cp "$fallback_copied" "$docker_dir/docker-compose.yml"
        fi

        if [ ! -f "$docker_dir/docker-compose.yml" ]; then
            log_warn "docker-compose.yml not found at: $docker_dir/docker-compose.yml"
            log_warn "Skipping Docker service startup"
            return 0
        fi
    fi

    cd "$docker_dir"

    # ------------------------------------------------------------------
    # 1. Generate .env file from credentials
    # ------------------------------------------------------------------
    log_info "Generating .env file from credentials..."
    local cred_dir="/tmp/chezmoi-${TENANT_NAME}/credentials"
    
    # Start with a header
    echo "# Generated by post-ansible-deploy.sh on $(date)" > .env

    # Append credentials if they exist
    if [ -f "${cred_dir}/credentials.env" ]; then
        cat "${cred_dir}/credentials.env" >> .env
        echo "" >> .env
    fi
    if [ -f "${cred_dir}/db-credentials.env" ]; then
        cat "${cred_dir}/db-credentials.env" >> .env
        echo "" >> .env
    fi

    # Append current environment variables that start with specific prefixes
    # This captures variables exported by export_tenant_env_vars (ENABLE_*) 
    # and other relevant vars (TENANT_*, DEPLOYMENT_*)
    env | grep -E '^(ENABLE_|TENANT_|DEPLOYMENT_|TIMEZONE|HOMEPAGE_)' >> .env || true
    
    log_info "Created .env file with $(wc -l < .env) lines"

    # ------------------------------------------------------------------
    # 2. Clean up conflicting networks
    # ------------------------------------------------------------------
    log_info "Cleaning up potential network conflicts..."
    local conflict_nets="paas_network unified_paas_frontend unified_paas_backend"
    for net in $conflict_nets; do
        if docker network ls --format '{{.Name}}' | grep -q "^${net}$"; then
            log_info "Removing conflicting network: $net"
            docker network rm "$net" || log_warn "Failed to remove network $net (might be in use)"
        fi
    done

    # Validate docker-compose.yml
    log_info "Validating Docker Compose configuration..."
    if ! docker compose config > /dev/null; then
        error_exit "Invalid docker-compose.yml configuration" 1
    fi

    # Determine which services actually exist in the compose file and filter arrays accordingly
    local available_services
    available_services="$(docker compose config --services | tr '\n' ' ' | sed 's/  */ /g')"
    filter_services_defined() {
        local filtered=()
        for svc in "$@"; do
            # skip empty entries
            if [ -z "${svc// /}" ]; then
                continue
            fi
            if echo " $available_services " | grep -q " $svc "; then
                filtered+=("$svc")
            else
                # Emit to stderr so mapfile (stdout) only captures service names
                printf "[WARN] Skipping service '%s' (not defined in docker-compose.yml)\n" "$svc" 1>&2
            fi
        done
        printf "%s\n" "${filtered[@]}"
    }

    mapfile -t CORE_SERVICES < <(filter_services_defined "${CORE_SERVICES[@]}")
    mapfile -t LANDING_SERVICES < <(filter_services_defined "${LANDING_SERVICES[@]}")
    mapfile -t SELECTED_SERVICES < <(filter_services_defined "${SELECTED_SERVICES[@]}")

    # Pull images
    log_info "Pulling Docker images..."
    docker compose pull || log_warn "Some images failed to pull"

    ensure_docker_networks

    start_service_group "core reverse-proxy stack" "${CORE_SERVICES[@]}"
    start_service_group "landing/Homepage stack" "${LANDING_SERVICES[@]}"
    if [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
        start_service_group "tenant-selected services" "${SELECTED_SERVICES[@]}"
    else
        log_info "No tenant-selected services to start"
    fi

    # Show service status
    log_info "Service status:"
    docker compose ps
}

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
        local running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
        log_info "Running containers: $running_containers"

        # Wait for services to be healthy
        log_info "Waiting for services to become healthy (30s)..."
        sleep 30

        # Check health status
        docker compose ps

        log_info "Deployment verification completed"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_step "Starting Post-Ansible Deployment"
    log_info "Log file: $LOG_FILE"

    validate_arguments "$@"
    check_prerequisites
    load_credentials
    export_tenant_env_vars
    initialize_chezmoi
    prepare_chezmoi_data
    apply_chezmoi_configuration

    if [ "$DEPLOYMENT_RUNTIME" = "docker" ]; then
        start_docker_services
        verify_deployment
    fi

    log_step "Post-Ansible Deployment Completed Successfully!"
    log_info "Deployment Summary:"
    log_info "  Tenant: $TENANT_NAME"
    log_info "  Runtime: $DEPLOYMENT_RUNTIME"
    log_info "  Domain: $TENANT_DOMAIN"

    if [ "$DEPLOYMENT_RUNTIME" = "docker" ]; then
        log_info ""
        log_info "Access your services at:"
        log_info "  Dashboard: https://${TENANT_DOMAIN}"
        log_info "  Traefik: https://traefik.${TENANT_DOMAIN}"
    fi

    log_info ""
    log_info "For more information, check the log file: $LOG_FILE"
}

# Start logging
setup_logging

# Run main function
main "$@"
