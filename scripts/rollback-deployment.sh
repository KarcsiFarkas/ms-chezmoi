#!/usr/bin/env bash
# ============================================================================
# Deployment Rollback Script (VM-Side)
# ============================================================================
# Performs rollback to previous deployment configuration
#
# Usage: ./rollback-deployment.sh [--snapshot SNAPSHOT_ID] [--dry-run]
# ============================================================================

set -euo pipefail

DEPLOYMENT_DIR="${HOME}/paas-deployment"
BACKUP_DIR="${DEPLOYMENT_DIR}/backups"
STATE_FILE="/opt/deployment-state.yml"
DRY_RUN=false
SNAPSHOT_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --snapshot) SNAPSHOT_ID="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) shift ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================================
# Rollback Functions
# ============================================================================

find_latest_backup() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "No backups directory found"
        return 1
    fi

    local latest
    latest=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | head -1)

    if [ -z "$latest" ]; then
        log_error "No backups found"
        return 1
    fi

    echo "$latest"
}

create_current_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/backup-before-rollback-$timestamp.tar.gz"

    log_info "Creating backup of current state..."

    mkdir -p "$BACKUP_DIR"

    tar -czf "$backup_file" \
        -C "$DEPLOYMENT_DIR" \
        docker-compose.yml .env configs/ 2>/dev/null || true

    log_info "Backup created: $backup_file"
}

stop_services() {
    log_info "Stopping current services..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would stop services"
        return 0
    fi

    cd "$DEPLOYMENT_DIR" || return 1
    docker compose down || {
        log_warn "Graceful shutdown failed, forcing stop..."
        docker compose kill
    }

    log_info "Services stopped"
}

restore_backup() {
    local backup_file="$1"

    log_info "Restoring from backup: $backup_file"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would restore from: $backup_file"
        return 0
    fi

    # Extract backup
    tar -xzf "$backup_file" -C "$DEPLOYMENT_DIR"

    log_info "Backup restored"
}

start_services() {
    log_info "Starting services from restored configuration..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would start services"
        return 0
    fi

    cd "$DEPLOYMENT_DIR" || return 1
    docker compose up -d

    log_info "Services started"
}

verify_rollback() {
    log_info "Verifying rollback..."

    sleep 10

    local running
    running=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)

    log_info "Running containers: $running"

    if [ "$running" -gt 0 ]; then
        log_info "✅ Rollback verification passed"
        return 0
    else
        log_error "❌ No containers running after rollback"
        return 1
    fi
}

# ============================================================================
# Main Rollback
# ============================================================================

main() {
    log_info "==================================="
    log_info "Deployment Rollback"
    log_info "==================================="

    # Find backup to restore
    local backup_to_restore

    if [ -n "$SNAPSHOT_ID" ]; then
        backup_to_restore="$BACKUP_DIR/backup-$SNAPSHOT_ID.tar.gz"

        if [ ! -f "$backup_to_restore" ]; then
            log_error "Snapshot not found: $SNAPSHOT_ID"
            exit 1
        fi
    else
        backup_to_restore=$(find_latest_backup) || exit 1
    fi

    log_info "Rollback target: $backup_to_restore"

    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi

    # Perform rollback
    create_current_backup
    stop_services
    restore_backup "$backup_to_restore"
    start_services

    if [ "$DRY_RUN" = false ]; then
        verify_rollback || {
            log_error "Rollback verification failed!"
            exit 1
        }
    fi

    log_info "==================================="
    log_info "✅ Rollback completed successfully"
    log_info "==================================="
}

main "$@"
