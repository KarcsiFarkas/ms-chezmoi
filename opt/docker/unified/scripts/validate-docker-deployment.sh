#!/usr/bin/env bash
# ============================================================================
# Docker Deployment Validation Script
# ============================================================================
# This script validates the system is ready for Docker deployment by checking:
# - Docker installation and version
# - docker compose plugin availability
# - Required ports availability
# - Sufficient disk space
# - CPU and RAM requirements
# - No conflicting containers
# - Environment variable configuration
# - docker-compose.yml syntax
#
# Usage:
#   ./validate-docker-deployment.sh [options]
#
# Options:
#   --skip-ports      Skip port availability checks
#   --skip-resources  Skip resource (CPU/RAM/disk) checks
#   --skip-docker     Skip Docker installation checks
#   --quiet           Minimal output (errors only)
#   --help            Show this help message
#
# Exit Codes:
#   0 - All validations passed
#   1 - Critical validation failed
#   2 - Warning validation failed (can proceed with caution)
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
ENV_FILE="${COMPOSE_DIR}/.env"

# Validation flags
SKIP_PORTS=false
SKIP_RESOURCES=false
SKIP_DOCKER=false
QUIET=false

# Minimum requirements
MIN_DOCKER_VERSION="24.0"
MIN_DISK_SPACE_GB=20
MIN_RAM_GB=4
MIN_CPU_CORES=2

# Required ports for core services
REQUIRED_PORTS=(80 443 8080)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Validation counters
ERRORS=0
WARNINGS=0
CHECKS=0

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    if [ "$QUIET" = false ]; then
        echo -e "${GREEN}✓${NC} $*"
    fi
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_check() {
    if [ "$QUIET" = false ]; then
        echo -e "${CYAN}→${NC} $*"
    fi
}

log_section() {
    if [ "$QUIET" = false ]; then
        echo -e "\n${BOLD}${BLUE}$*${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

log_result() {
    if [ "$QUIET" = false ]; then
        echo ""
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

version_ge() {
    # Compare versions (returns 0 if $1 >= $2)
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"

    ((CHECKS++))
    log_check "Checking for $name..."

    if command -v "$cmd" &> /dev/null; then
        log_info "$name is installed"
        return 0
    else
        log_error "$name is not installed"
        ((ERRORS++))
        return 1
    fi
}

check_port() {
    local port="$1"

    ((CHECKS++))

    if netstat -tuln 2>/dev/null | grep -q ":${port} " || \
       ss -tuln 2>/dev/null | grep -q ":${port} "; then
        log_error "Port $port is already in use"
        ((ERRORS++))
        return 1
    else
        log_info "Port $port is available"
        return 0
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_docker_installation() {
    log_section "Docker Installation"

    if [ "$SKIP_DOCKER" = true ]; then
        log_warn "Skipping Docker installation checks"
        return 0
    fi

    # Check if Docker is installed
    if ! check_command docker "Docker"; then
        log_error "Docker is not installed. Please install Docker first."
        log_error "Visit: https://docs.docker.com/engine/install/"
        return 1
    fi

    # Check Docker version
    ((CHECKS++))
    log_check "Checking Docker version..."

    local docker_version
    docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -n1)

    if version_ge "$docker_version" "$MIN_DOCKER_VERSION"; then
        log_info "Docker version $docker_version (>= $MIN_DOCKER_VERSION required)"
    else
        log_error "Docker version $docker_version is too old (>= $MIN_DOCKER_VERSION required)"
        ((ERRORS++))
        return 1
    fi

    # Check if Docker daemon is running
    ((CHECKS++))
    log_check "Checking Docker daemon..."

    if docker info &> /dev/null; then
        log_info "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        log_error "Start it with: sudo systemctl start docker"
        ((ERRORS++))
        return 1
    fi

    # Check for docker compose plugin
    ((CHECKS++))
    log_check "Checking Docker Compose..."

    if docker compose version &> /dev/null; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_info "Docker Compose v2 plugin installed (version: $compose_version)"
    else
        log_error "Docker Compose v2 plugin is not installed"
        log_error "Install it with: sudo apt-get install docker-compose-plugin"
        ((ERRORS++))
        return 1
    fi

    # Check user permissions
    ((CHECKS++))
    log_check "Checking Docker permissions..."

    if docker ps &> /dev/null; then
        log_info "Current user can run Docker commands"
    else
        log_warn "Current user cannot run Docker without sudo"
        log_warn "Consider adding user to docker group: sudo usermod -aG docker \$USER"
        ((WARNINGS++))
    fi

    log_result
    return 0
}

validate_system_resources() {
    log_section "System Resources"

    if [ "$SKIP_RESOURCES" = true ]; then
        log_warn "Skipping system resource checks"
        return 0
    fi

    # Check available RAM
    ((CHECKS++))
    log_check "Checking available RAM..."

    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))

    if [ "$total_ram_gb" -ge "$MIN_RAM_GB" ]; then
        log_info "RAM: ${total_ram_gb}GB (>= ${MIN_RAM_GB}GB required)"
    else
        log_warn "RAM: ${total_ram_gb}GB (< ${MIN_RAM_GB}GB recommended)"
        log_warn "You may experience performance issues"
        ((WARNINGS++))
    fi

    # Check CPU cores
    ((CHECKS++))
    log_check "Checking CPU cores..."

    local cpu_cores
    cpu_cores=$(nproc)

    if [ "$cpu_cores" -ge "$MIN_CPU_CORES" ]; then
        log_info "CPU cores: $cpu_cores (>= $MIN_CPU_CORES required)"
    else
        log_warn "CPU cores: $cpu_cores (< $MIN_CPU_CORES recommended)"
        ((WARNINGS++))
    fi

    # Check disk space
    ((CHECKS++))
    log_check "Checking disk space..."

    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ "$available_gb" -ge "$MIN_DISK_SPACE_GB" ]; then
        log_info "Disk space: ${available_gb}GB available (>= ${MIN_DISK_SPACE_GB}GB required)"
    else
        log_error "Disk space: ${available_gb}GB available (< ${MIN_DISK_SPACE_GB}GB required)"
        log_error "Free up disk space before deploying"
        ((ERRORS++))
    fi

    # Check Docker root directory disk space
    ((CHECKS++))
    log_check "Checking Docker storage..."

    if docker info &> /dev/null; then
        local docker_root
        docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")

        local docker_disk_gb
        docker_disk_gb=$(df -BG "$docker_root" | awk 'NR==2 {print $4}' | sed 's/G//')

        if [ "$docker_disk_gb" -ge 10 ]; then
            log_info "Docker storage: ${docker_disk_gb}GB available"
        else
            log_warn "Docker storage: ${docker_disk_gb}GB available (< 10GB recommended)"
            ((WARNINGS++))
        fi
    fi

    log_result
    return 0
}

validate_network_ports() {
    log_section "Network Port Availability"

    if [ "$SKIP_PORTS" = true ]; then
        log_warn "Skipping port availability checks"
        return 0
    fi

    # Check if netstat or ss is available
    if ! command -v netstat &> /dev/null && ! command -v ss &> /dev/null; then
        log_warn "Neither netstat nor ss is installed - cannot check ports"
        log_warn "Install net-tools or iproute2 package"
        ((WARNINGS++))
        return 0
    fi

    log_check "Checking required ports..."

    local ports_ok=true

    for port in "${REQUIRED_PORTS[@]}"; do
        if ! check_port "$port"; then
            ports_ok=false
        fi
    done

    if [ "$ports_ok" = true ]; then
        log_info "All required ports are available"
    else
        log_error "Some required ports are in use"
        log_error "Stop conflicting services or change port mappings"
    fi

    log_result
    return 0
}

validate_configuration_files() {
    log_section "Configuration Files"

    # Check if docker-compose.yml exists
    ((CHECKS++))
    log_check "Checking docker-compose.yml..."

    if [ -f "$COMPOSE_FILE" ]; then
        log_info "docker-compose.yml found: $COMPOSE_FILE"
    else
        log_error "docker-compose.yml not found: $COMPOSE_FILE"
        ((ERRORS++))
        return 1
    fi

    # Validate docker-compose.yml syntax
    ((CHECKS++))
    log_check "Validating docker-compose.yml syntax..."

    if docker compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
        log_info "docker-compose.yml syntax is valid"
    else
        log_error "docker-compose.yml has syntax errors"
        log_error "Run: docker compose config"
        ((ERRORS++))
        return 1
    fi

    # Check if .env file exists
    ((CHECKS++))
    log_check "Checking .env file..."

    if [ -f "$ENV_FILE" ]; then
        log_info ".env file found: $ENV_FILE"
    else
        log_warn ".env file not found (will use defaults or template values)"
        log_warn "Consider creating .env from .env.example"
        ((WARNINGS++))
    fi

    # Validate required environment variables
    if [ -f "$ENV_FILE" ]; then
        ((CHECKS++))
        log_check "Validating environment variables..."

        local required_vars=(
            "TENANT_DOMAIN"
            "TRAEFIK_ACME_EMAIL"
            "REDIS_PASSWORD"
        )

        local missing_vars=()

        for var in "${required_vars[@]}"; do
            if ! grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
                missing_vars+=("$var")
            fi
        done

        if [ ${#missing_vars[@]} -eq 0 ]; then
            log_info "All required environment variables are set"
        else
            log_warn "Missing required environment variables: ${missing_vars[*]}"
            log_warn "Set them in $ENV_FILE"
            ((WARNINGS++))
        fi
    fi

    log_result
    return 0
}

validate_docker_networks() {
    log_section "Docker Networks"

    # Check for conflicting networks
    ((CHECKS++))
    log_check "Checking for network conflicts..."

    local conflicting_networks=()

    if docker network ls --format '{{.Name}}' | grep -q '^paas_frontend$'; then
        conflicting_networks+=("paas_frontend")
    fi

    if docker network ls --format '{{.Name}}' | grep -q '^paas_backend$'; then
        conflicting_networks+=("paas_backend")
    fi

    if [ ${#conflicting_networks[@]} -eq 0 ]; then
        log_info "No network conflicts found"
    else
        log_warn "Found existing networks: ${conflicting_networks[*]}"
        log_warn "These will be reused if compatible"
        ((WARNINGS++))
    fi

    log_result
    return 0
}

validate_existing_containers() {
    log_section "Existing Containers"

    # Check for conflicting containers
    ((CHECKS++))
    log_check "Checking for conflicting containers..."

    local conflicting_containers=()
    local container_names=(
        "paas-traefik"
        "paas-authentik-server"
        "paas-vaultwarden"
        "paas-homepage"
        "paas-nextcloud"
        "paas-immich-server"
        "paas-jellyfin"
        "paas-gitea"
    )

    for container in "${container_names[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            conflicting_containers+=("$container")
        fi
    done

    if [ ${#conflicting_containers[@]} -eq 0 ]; then
        log_info "No conflicting containers found"
    else
        log_warn "Found existing containers: ${conflicting_containers[*]}"
        log_warn "Stop and remove them with: docker compose down"
        ((WARNINGS++))
    fi

    log_result
    return 0
}

validate_data_directory() {
    log_section "Data Directory"

    local data_dir="${DOCKER_DATA_DIR:-/opt/docker-data}"

    # Check if data directory exists
    ((CHECKS++))
    log_check "Checking data directory: $data_dir"

    if [ -d "$data_dir" ]; then
        log_info "Data directory exists: $data_dir"

        # Check permissions
        if [ -w "$data_dir" ]; then
            log_info "Data directory is writable"
        else
            log_error "Data directory is not writable: $data_dir"
            log_error "Run: sudo chown -R \$USER:\$USER $data_dir"
            ((ERRORS++))
        fi
    else
        log_warn "Data directory does not exist: $data_dir"
        log_warn "Run: ./scripts/prepare-docker-volumes.sh"
        ((WARNINGS++))
    fi

    log_result
    return 0
}

# ============================================================================
# Summary and Reporting
# ============================================================================

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BOLD}Validation Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Total checks: $CHECKS"

    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ All validations passed!${NC}"
        echo ""
        echo "Your system is ready for Docker deployment."
        echo ""
        echo "Next steps:"
        echo "  1. Review .env configuration"
        echo "  2. Run: ./scripts/prepare-docker-volumes.sh"
        echo "  3. Run: docker compose up -d"
        echo ""
        return 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "${YELLOW}${BOLD}⚠ Validation completed with $WARNINGS warning(s)${NC}"
        echo ""
        echo "You can proceed with deployment, but review warnings above."
        echo ""
        return 2
    else
        echo -e "${RED}${BOLD}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
        echo ""
        echo "Fix the errors above before deploying."
        echo ""
        return 1
    fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-ports)
                SKIP_PORTS=true
                shift
                ;;
            --skip-resources)
                SKIP_RESOURCES=true
                shift
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [ "$QUIET" = false ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${BOLD}${CYAN}Docker Deployment Validation${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    # Run validations
    validate_docker_installation
    validate_system_resources
    validate_network_ports
    validate_configuration_files
    validate_docker_networks
    validate_existing_containers
    validate_data_directory

    # Print summary and exit with appropriate code
    print_summary
}

# Run main function
main "$@"
