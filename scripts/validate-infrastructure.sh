#!/usr/bin/env bash
# ============================================================================
# Infrastructure Validation Script (VM-Side)
# ============================================================================
# This script runs on the target VM to validate infrastructure readiness
# before deployment. It performs comprehensive checks on system resources,
# network connectivity, software dependencies, and security configuration.
#
# Usage:
#   ./validate-infrastructure.sh [--json] [--output FILE]
#
# Options:
#   --json          Output results in JSON format
#   --output FILE   Write results to file instead of stdout
#   --strict        Exit with error on warnings (default: errors only)
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_NAME="Infrastructure Validation"
VERSION="1.0.0"

# Requirements (can be overridden via environment variables)
MIN_CPU_CORES="${MIN_CPU_CORES:-4}"
MIN_RAM_GB="${MIN_RAM_GB:-8}"
MIN_DISK_GB="${MIN_DISK_GB:-50}"
DOCKER_MIN_VERSION="${DOCKER_MIN_VERSION:-24.0.0}"

# Output configuration
JSON_OUTPUT=false
OUTPUT_FILE=""
STRICT_MODE=false

# Result tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

RESULTS=()

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--json] [--output FILE] [--strict]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}[OK]${NC} $*"
    fi
}

log_warn() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}[WARN]${NC} $*"
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}[ERROR]${NC} $*"
    fi
}

# ============================================================================
# Result Tracking
# ============================================================================

add_result() {
    local check_name="$1"
    local status="$2"  # pass, fail, warn
    local message="$3"
    local details="${4:-}"

    ((TOTAL_CHECKS++))

    case "$status" in
        pass)
            ((PASSED_CHECKS++))
            log_success "✓ $check_name: $message"
            ;;
        fail)
            ((FAILED_CHECKS++))
            log_error "✗ $check_name: $message"
            ;;
        warn)
            ((WARNING_CHECKS++))
            log_warn "⚠ $check_name: $message"
            ;;
    esac

    # Store result for JSON output
    RESULTS+=("{\"check\":\"$check_name\",\"status\":\"$status\",\"message\":\"$message\",\"details\":$details}")
}

# ============================================================================
# Validation Checks
# ============================================================================

check_cpu_cores() {
    local cores
    cores=$(nproc)

    if [ "$cores" -ge "$MIN_CPU_CORES" ]; then
        add_result "CPU Cores" "pass" "$cores cores available" "{\"cores\":$cores,\"required\":$MIN_CPU_CORES}"
    else
        add_result "CPU Cores" "warn" "$cores cores (minimum: $MIN_CPU_CORES)" "{\"cores\":$cores,\"required\":$MIN_CPU_CORES}"
    fi
}

check_ram() {
    local ram_gb
    ram_gb=$(free -g | awk '/^Mem:/ {print $2}')

    if [ "$ram_gb" -ge "$MIN_RAM_GB" ]; then
        add_result "RAM" "pass" "${ram_gb}GB available" "{\"ram_gb\":$ram_gb,\"required_gb\":$MIN_RAM_GB}"
    else
        add_result "RAM" "fail" "${ram_gb}GB (minimum: ${MIN_RAM_GB}GB)" "{\"ram_gb\":$ram_gb,\"required_gb\":$MIN_RAM_GB}"
    fi
}

check_disk_space() {
    local disk_gb
    disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ "$disk_gb" -ge "$MIN_DISK_GB" ]; then
        add_result "Disk Space" "pass" "${disk_gb}GB free" "{\"disk_gb\":$disk_gb,\"required_gb\":$MIN_DISK_GB}"
    else
        add_result "Disk Space" "fail" "${disk_gb}GB (minimum: ${MIN_DISK_GB}GB)" "{\"disk_gb\":$disk_gb,\"required_gb\":$MIN_DISK_GB}"
    fi
}

check_swap() {
    local swap_gb
    swap_gb=$(free -g | awk '/^Swap:/ {print $2}')

    if [ "$swap_gb" -gt 0 ]; then
        add_result "Swap Memory" "pass" "${swap_gb}GB configured" "{\"swap_gb\":$swap_gb}"
    else
        add_result "Swap Memory" "warn" "No swap configured" "{\"swap_gb\":0}"
    fi
}

check_dns() {
    if nslookup google.com >/dev/null 2>&1; then
        add_result "DNS Resolution" "pass" "Working" "{}"
    else
        add_result "DNS Resolution" "fail" "Failed" "{}"
    fi
}

check_internet() {
    if curl -sSf -m 5 https://www.google.com >/dev/null 2>&1; then
        add_result "Internet Connectivity" "pass" "Verified" "{}"
    else
        add_result "Internet Connectivity" "fail" "No connectivity" "{}"
    fi
}

check_ports() {
    local required_ports=(22 80 443 5432 6379)
    local used_ports=()

    for port in "${required_ports[@]}"; do
        if ss -tuln | grep -q ":${port} "; then
            used_ports+=("$port")
        fi
    done

    if [ ${#used_ports[@]} -eq 0 ]; then
        add_result "Port Availability" "pass" "All required ports available" "{\"required\":[${required_ports[*]}]}"
    else
        local used_str=$(IFS=,; echo "${used_ports[*]}")
        add_result "Port Availability" "warn" "Ports in use: $used_str" "{\"used\":[$used_str]}"
    fi
}

check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        local version
        version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        add_result "Docker Installation" "pass" "Version $version" "{\"version\":\"$version\"}"
        return 0
    else
        add_result "Docker Installation" "fail" "Not installed" "{}"
        return 1
    fi
}

check_docker_version() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi

    local version
    version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)

    if [ "$(printf '%s\n' "$DOCKER_MIN_VERSION" "$version" | sort -V | head -n1)" = "$DOCKER_MIN_VERSION" ]; then
        add_result "Docker Version" "pass" "$version >= $DOCKER_MIN_VERSION" "{\"version\":\"$version\",\"required\":\"$DOCKER_MIN_VERSION\"}"
    else
        add_result "Docker Version" "fail" "$version < $DOCKER_MIN_VERSION" "{\"version\":\"$version\",\"required\":\"$DOCKER_MIN_VERSION\"}"
    fi
}

check_docker_service() {
    if systemctl is-active --quiet docker; then
        add_result "Docker Service" "pass" "Running" "{}"
    else
        add_result "Docker Service" "fail" "Not running" "{}"
    fi
}

check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        local version
        version=$(docker compose version --short 2>/dev/null || echo "unknown")
        add_result "Docker Compose" "pass" "Installed (v$version)" "{\"version\":\"$version\"}"
    else
        add_result "Docker Compose" "fail" "Not installed or not accessible" "{}"
    fi
}

check_docker_permissions() {
    if docker ps >/dev/null 2>&1; then
        add_result "Docker Permissions" "pass" "User can access Docker" "{}"
    else
        add_result "Docker Permissions" "fail" "User cannot access Docker socket" "{\"fix\":\"sudo usermod -aG docker $(whoami)\"}"
    fi
}

check_kernel_modules() {
    local required_modules=("overlay" "br_netfilter")
    local missing=()

    for module in "${required_modules[@]}"; do
        if ! lsmod | grep -q "^$module "; then
            missing+=("$module")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        add_result "Kernel Modules" "pass" "All required modules loaded" "{\"modules\":[\"overlay\",\"br_netfilter\"]}"
    else
        local missing_str=$(IFS=,; echo "${missing[*]}")
        add_result "Kernel Modules" "warn" "Missing: $missing_str" "{\"missing\":[$missing_str]}"
    fi
}

check_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        if sudo ufw status | grep -q "Status: active"; then
            add_result "Firewall" "pass" "UFW active" "{}"
        else
            add_result "Firewall" "warn" "UFW inactive" "{}"
        fi
    else
        add_result "Firewall" "warn" "UFW not installed" "{}"
    fi
}

check_selinux() {
    if command -v getenforce >/dev/null 2>&1; then
        local status
        status=$(getenforce)

        if [ "$status" = "Enforcing" ]; then
            add_result "SELinux" "warn" "Enforcing (may block Docker)" "{\"status\":\"$status\"}"
        else
            add_result "SELinux" "pass" "Status: $status" "{\"status\":\"$status\"}"
        fi
    else
        add_result "SELinux" "pass" "Not installed" "{}"
    fi
}

check_required_packages() {
    local required=("git" "jq" "curl" "python3")
    local missing=()

    for pkg in "${required[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        add_result "Required Packages" "pass" "All installed" "{\"packages\":[\"${required[*]}\"]}"
    else
        local missing_str=$(IFS=,; echo "${missing[*]}")
        add_result "Required Packages" "fail" "Missing: $missing_str" "{\"missing\":[$missing_str]}"
    fi
}

# ============================================================================
# Main Validation
# ============================================================================

run_validation() {
    log_info "Starting infrastructure validation..."
    log_info "Minimum requirements: ${MIN_CPU_CORES} cores, ${MIN_RAM_GB}GB RAM, ${MIN_DISK_GB}GB disk"
    echo

    # System Resources
    check_cpu_cores
    check_ram
    check_disk_space
    check_swap

    # Network
    check_dns
    check_internet
    check_ports

    # Software
    check_required_packages

    # Docker
    if check_docker_installed; then
        check_docker_version
        check_docker_service
        check_docker_compose
        check_docker_permissions
        check_kernel_modules
    fi

    # Security
    check_firewall
    check_selinux
}

# ============================================================================
# Output Results
# ============================================================================

output_results() {
    if [ "$JSON_OUTPUT" = true ]; then
        # JSON output
        local results_json=$(printf '%s\n' "${RESULTS[@]}" | paste -sd ',' -)

        local output="{
  \"validation\": {
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"hostname\": \"$(hostname)\",
    \"total_checks\": $TOTAL_CHECKS,
    \"passed\": $PASSED_CHECKS,
    \"failed\": $FAILED_CHECKS,
    \"warnings\": $WARNING_CHECKS,
    \"success\": $([ $FAILED_CHECKS -eq 0 ] && echo "true" || echo "false")
  },
  \"results\": [$results_json]
}"

        if [ -n "$OUTPUT_FILE" ]; then
            echo "$output" > "$OUTPUT_FILE"
        else
            echo "$output"
        fi
    else
        # Human-readable output
        echo
        echo "========================================="
        echo "Validation Summary"
        echo "========================================="
        echo "Total checks:    $TOTAL_CHECKS"
        echo "Passed:          $PASSED_CHECKS"
        echo "Failed:          $FAILED_CHECKS"
        echo "Warnings:        $WARNING_CHECKS"
        echo "========================================="

        if [ $FAILED_CHECKS -eq 0 ] && [ $WARNING_CHECKS -eq 0 ]; then
            log_success "All validation checks passed!"
        elif [ $FAILED_CHECKS -eq 0 ]; then
            log_warn "Validation passed with $WARNING_CHECKS warning(s)"
        else
            log_error "Validation failed with $FAILED_CHECKS error(s)"
        fi
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    run_validation
    output_results

    # Exit code
    if [ $FAILED_CHECKS -gt 0 ]; then
        exit 1
    elif [ "$STRICT_MODE" = true ] && [ $WARNING_CHECKS -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

main "$@"
