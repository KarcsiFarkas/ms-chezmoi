#!/usr/bin/env bash
# ============================================================================
# Deployment Monitoring Script (VM-Side)
# ============================================================================
# Monitors deployment health, collects metrics, and reports status
#
# Usage: ./monitor-deployment.sh [--json] [--watch SECONDS]
# ============================================================================

set -euo pipefail

DEPLOYMENT_DIR="${HOME}/paas-deployment"
JSON_OUTPUT=false
WATCH_MODE=false
WATCH_INTERVAL=30

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json) JSON_OUTPUT=true; shift ;;
        --watch) WATCH_MODE=true; WATCH_INTERVAL="${2:-30}"; shift 2 ;;
        *) shift ;;
    esac
done

# ============================================================================
# Health Check Functions
# ============================================================================

check_container_health() {
    if ! cd "$DEPLOYMENT_DIR" 2>/dev/null; then
        echo "{\"error\":\"Deployment directory not found\"}"
        return 1
    fi

    local containers
    containers=$(docker compose ps --format json 2>/dev/null || echo "[]")

    local total=0
    local running=0
    local healthy=0

    if [ -n "$containers" ] && [ "$containers" != "[]" ]; then
        total=$(echo "$containers" | jq -s 'length')
        running=$(echo "$containers" | jq -s '[.[] | select(.State == "running")] | length')
        healthy=$(echo "$containers" | jq -s '[.[] | select(.Health == "healthy" or (.Health == null and .State == "running"))] | length')
    fi

    echo "{\"total\":$total,\"running\":$running,\"healthy\":$healthy,\"containers\":$containers}"
}

check_resource_usage() {
    local cpu_usage
    local mem_usage
    local disk_usage

    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    mem_usage=$(free | awk '/Mem:/ {printf "%.1f", $3/$2 * 100}')
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

    echo "{\"cpu_percent\":$cpu_usage,\"memory_percent\":$mem_usage,\"disk_percent\":$disk_usage}"
}

check_network_connectivity() {
    local traefik_ok=false
    local internet_ok=false

    if curl -sf http://localhost:80 >/dev/null 2>&1; then
        traefik_ok=true
    fi

    if curl -sf -m 2 https://www.google.com >/dev/null 2>&1; then
        internet_ok=true
    fi

    echo "{\"traefik\":$traefik_ok,\"internet\":$internet_ok}"
}

# ============================================================================
# Main Monitoring
# ============================================================================

collect_metrics() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local health
    local resources
    local network

    health=$(check_container_health)
    resources=$(check_resource_usage)
    network=$(check_network_connectivity)

    if [ "$JSON_OUTPUT" = true ]; then
        echo "{
  \"timestamp\": \"$timestamp\",
  \"hostname\": \"$(hostname)\",
  \"health\": $health,
  \"resources\": $resources,
  \"network\": $network
}"
    else
        echo "==================================="
        echo "Deployment Health - $(date)"
        echo "==================================="
        echo "Containers:"
        echo "$health" | jq -r '"  Total: \(.total)  Running: \(.running)  Healthy: \(.healthy)"'
        echo
        echo "Resources:"
        echo "$resources" | jq -r '"  CPU: \(.cpu_percent)%  Memory: \(.memory_percent)%  Disk: \(.disk_percent)%"'
        echo
        echo "Network:"
        echo "$network" | jq -r '"  Traefik: \(.traefik)  Internet: \(.internet)"'
        echo "==================================="
    fi
}

# ============================================================================
# Watch Mode
# ============================================================================

if [ "$WATCH_MODE" = true ]; then
    while true; do
        clear
        collect_metrics
        sleep "$WATCH_INTERVAL"
    done
else
    collect_metrics
fi
