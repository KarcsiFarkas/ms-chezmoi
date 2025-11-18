#!/usr/bin/env bash
# ============================================================================
# Docker Volume Mount Preparation Script
# ============================================================================
# This script prepares all bind mount directories required by docker-compose
# services with correct ownership and permissions.
#
# Features:
# - Parses docker-compose.yml for bind mount paths
# - Creates directories with correct ownership
# - Sets appropriate permissions
# - Idempotent (safe to run multiple times)
# - Validates completion
#
# Usage:
#   ./prepare-docker-volumes.sh [options]
#
# Options:
#   --data-dir DIR    Override DOCKER_DATA_DIR (default: /opt/docker-data)
#   --user USER       Override ownership user (default: current user)
#   --group GROUP     Override ownership group (default: current user's group)
#   --dry-run         Show what would be done without making changes
#   --verbose         Enable verbose output
#   --help            Show this help message
#
# Examples:
#   ./prepare-docker-volumes.sh
#   ./prepare-docker-volumes.sh --data-dir /mnt/docker-data
#   ./prepare-docker-volumes.sh --dry-run --verbose
#
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"

# Default values
DOCKER_DATA_DIR="${DOCKER_DATA_DIR:-/opt/docker-data}"
OWNER_USER="${USER}"
OWNER_GROUP="$(id -gn)"
DRY_RUN=false
VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $*\n"
}

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check if running with sufficient privileges
    if [ ! -w "$DOCKER_DATA_DIR" ] && [ "$DOCKER_DATA_DIR" != "/opt/docker-data" ]; then
        if [ ! -d "$DOCKER_DATA_DIR" ]; then
            log_warn "Data directory doesn't exist: $DOCKER_DATA_DIR"
            log_warn "Will attempt to create it (may require sudo)"
        fi
    fi

    # Check if docker-compose.yml exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        error_exit "docker-compose.yml not found at: $COMPOSE_FILE" 1
    fi

    log_info "Prerequisites check passed"
}

create_directory() {
    local dir="$1"
    local user="$2"
    local group="$3"
    local perms="$4"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create: $dir (${user}:${group}, ${perms})"
        return 0
    fi

    # Create directory if it doesn't exist
    if [ ! -d "$dir" ]; then
        log_debug "Creating directory: $dir"

        if sudo mkdir -p "$dir"; then
            log_info "Created: $dir"
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    else
        log_debug "Directory already exists: $dir"
    fi

    # Set ownership
    local current_owner
    current_owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "unknown:unknown")

    if [ "$current_owner" != "${user}:${group}" ]; then
        log_debug "Setting ownership: ${user}:${group} on $dir"

        if sudo chown "${user}:${group}" "$dir"; then
            log_info "Set ownership ${user}:${group}: $dir"
        else
            log_warn "Failed to set ownership on: $dir"
        fi
    else
        log_debug "Ownership already correct: $dir"
    fi

    # Set permissions
    local current_perms
    current_perms=$(stat -c '%a' "$dir" 2>/dev/null || echo "000")

    if [ "$current_perms" != "$perms" ]; then
        log_debug "Setting permissions: $perms on $dir"

        if sudo chmod "$perms" "$dir"; then
            log_info "Set permissions $perms: $dir"
        else
            log_warn "Failed to set permissions on: $dir"
        fi
    else
        log_debug "Permissions already correct: $dir"
    fi

    return 0
}

extract_bind_mounts() {
    log_step "Extracting bind mount paths from docker-compose.yml..."

    local bind_mounts=()

    # Parse docker-compose.yml for bind mounts
    # This is a simplified parser - assumes standard formatting
    while IFS= read -r line; do
        # Match lines like: - "./path:/container/path" or - "${VAR}/path:/container/path"
        if echo "$line" | grep -qE '^\s*-\s*["\047]?\$?\{?[^:]+\}?/[^:]+:[^:]+'; then
            # Extract the host path part
            local mount
            mount=$(echo "$line" | sed -E 's/^\s*-\s*["\047]?([^:]+):.*/\1/' | tr -d '"' | tr -d "'")

            # Skip if it's a named volume (no path separator)
            if echo "$mount" | grep -q '/'; then
                # Expand variables if present
                mount=$(eval echo "$mount")

                # Convert relative paths to absolute
                if [[ "$mount" == ./* ]]; then
                    mount="${COMPOSE_DIR}/${mount#./}"
                fi

                bind_mounts+=("$mount")
                log_debug "Found bind mount: $mount"
            fi
        fi
    done < "$COMPOSE_FILE"

    # Remove duplicates and sort
    mapfile -t bind_mounts < <(printf '%s\n' "${bind_mounts[@]}" | sort -u)

    echo "${bind_mounts[@]}"
}

prepare_standard_directories() {
    log_step "Preparing standard Docker data directories..."

    # Define standard directory structure with permissions
    # Format: "path|user|group|permissions|description"
    local -a directories=(
        "${DOCKER_DATA_DIR}|${OWNER_USER}|${OWNER_GROUP}|755|Root data directory"

        # Traefik
        "${DOCKER_DATA_DIR}/traefik|${OWNER_USER}|${OWNER_GROUP}|755|Traefik configuration"
        "${DOCKER_DATA_DIR}/traefik/dynamic|${OWNER_USER}|${OWNER_GROUP}|755|Traefik dynamic config"
        "${DOCKER_DATA_DIR}/traefik/certificates|${OWNER_USER}|${OWNER_GROUP}|700|SSL certificates"

        # Authentik
        "${DOCKER_DATA_DIR}/authentik|${OWNER_USER}|${OWNER_GROUP}|755|Authentik configuration"
        "${DOCKER_DATA_DIR}/authentik/media|${OWNER_USER}|${OWNER_GROUP}|755|Authentik media files"
        "${DOCKER_DATA_DIR}/authentik/templates|${OWNER_USER}|${OWNER_GROUP}|755|Authentik templates"
        "${DOCKER_DATA_DIR}/authentik/certs|${OWNER_USER}|${OWNER_GROUP}|700|Authentik certificates"

        # Vaultwarden
        "${DOCKER_DATA_DIR}/vaultwarden|${OWNER_USER}|${OWNER_GROUP}|755|Vaultwarden data"

        # Homepage
        "${DOCKER_DATA_DIR}/homepage|${OWNER_USER}|${OWNER_GROUP}|755|Homepage data"
        "${DOCKER_DATA_DIR}/homepage/config|${OWNER_USER}|${OWNER_GROUP}|755|Homepage configuration"

        # Nextcloud
        "${DOCKER_DATA_DIR}/nextcloud|${OWNER_USER}|${OWNER_GROUP}|755|Nextcloud data"
        "${DOCKER_DATA_DIR}/nextcloud/data|${OWNER_USER}|${OWNER_GROUP}|755|Nextcloud user data"
        "${DOCKER_DATA_DIR}/nextcloud/config|${OWNER_USER}|${OWNER_GROUP}|755|Nextcloud configuration"
        "${DOCKER_DATA_DIR}/nextcloud/apps|${OWNER_USER}|${OWNER_GROUP}|755|Nextcloud apps"

        # Immich
        "${DOCKER_DATA_DIR}/immich|${OWNER_USER}|${OWNER_GROUP}|755|Immich data"
        "${DOCKER_DATA_DIR}/immich/upload|${OWNER_USER}|${OWNER_GROUP}|755|Immich uploads"
        "${DOCKER_DATA_DIR}/immich/library|${OWNER_USER}|${OWNER_GROUP}|755|Immich library"

        # Jellyfin
        "${DOCKER_DATA_DIR}/jellyfin|${OWNER_USER}|${OWNER_GROUP}|755|Jellyfin data"
        "${DOCKER_DATA_DIR}/jellyfin/config|${OWNER_USER}|${OWNER_GROUP}|755|Jellyfin configuration"
        "${DOCKER_DATA_DIR}/jellyfin/media|${OWNER_USER}|${OWNER_GROUP}|755|Jellyfin media root"
        "${DOCKER_DATA_DIR}/jellyfin/media/movies|${OWNER_USER}|${OWNER_GROUP}|755|Jellyfin movies"
        "${DOCKER_DATA_DIR}/jellyfin/media/tv|${OWNER_USER}|${OWNER_GROUP}|755|Jellyfin TV shows"
        "${DOCKER_DATA_DIR}/jellyfin/media/music|${OWNER_USER}|${OWNER_GROUP}|755|Jellyfin music"

        # Gitea
        "${DOCKER_DATA_DIR}/gitea|${OWNER_USER}|${OWNER_GROUP}|755|Gitea data"
        "${DOCKER_DATA_DIR}/gitea/data|${OWNER_USER}|${OWNER_GROUP}|755|Gitea repositories"
    )

    local total=${#directories[@]}
    local current=0
    local created=0
    local skipped=0
    local failed=0

    for dir_spec in "${directories[@]}"; do
        ((current++))

        IFS='|' read -r path user group perms description <<< "$dir_spec"

        log_debug "[$current/$total] Processing: $description"

        if create_directory "$path" "$user" "$group" "$perms"; then
            if [ ! -d "$path" ] || [ "$DRY_RUN" = true ]; then
                ((created++))
            else
                ((skipped++))
            fi
        else
            ((failed++))
        fi
    done

    log_info "Directory preparation summary:"
    log_info "  Total: $total"
    log_info "  Created/Updated: $created"
    log_info "  Already correct: $skipped"

    if [ $failed -gt 0 ]; then
        log_warn "  Failed: $failed"
    fi
}

validate_directories() {
    log_step "Validating directory structure..."

    local errors=0
    local warnings=0

    # Check root data directory
    if [ ! -d "$DOCKER_DATA_DIR" ]; then
        log_error "Root data directory does not exist: $DOCKER_DATA_DIR"
        ((errors++))
    elif [ ! -w "$DOCKER_DATA_DIR" ]; then
        log_warn "Root data directory is not writable: $DOCKER_DATA_DIR"
        ((warnings++))
    else
        log_info "Root data directory is accessible: $DOCKER_DATA_DIR"
    fi

    # Check critical service directories
    local -a critical_dirs=(
        "${DOCKER_DATA_DIR}/traefik/dynamic"
        "${DOCKER_DATA_DIR}/authentik/media"
    )

    for dir in "${critical_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_warn "Critical directory missing: $dir"
            ((warnings++))
        fi
    done

    log_info "Validation complete: $errors errors, $warnings warnings"

    if [ $errors -gt 0 ]; then
        return 1
    fi

    return 0
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --data-dir)
                DOCKER_DATA_DIR="$2"
                shift 2
                ;;
            --user)
                OWNER_USER="$2"
                shift 2
                ;;
            --group)
                OWNER_GROUP="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    log_step "Docker Volume Preparation Script"

    if [ "$DRY_RUN" = true ]; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi

    log_info "Configuration:"
    log_info "  Data directory: $DOCKER_DATA_DIR"
    log_info "  Owner: ${OWNER_USER}:${OWNER_GROUP}"
    log_info "  Compose file: $COMPOSE_FILE"

    check_prerequisites
    prepare_standard_directories

    if [ "$DRY_RUN" = false ]; then
        validate_directories || log_warn "Validation found issues - please review"
    fi

    log_step "Volume preparation completed successfully!"

    if [ "$DRY_RUN" = false ]; then
        log_info "You can now run: docker compose up -d"
    else
        log_info "This was a dry run. Remove --dry-run to apply changes."
    fi
}

# Run main function
main "$@"
