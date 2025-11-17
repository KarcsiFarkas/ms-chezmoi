#!/usr/bin/env bash
set -euo pipefail

REQUIRED_TOOLS=(bash curl git jq yq python3 rsync tar)
MISSING=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING+=("$tool")
    fi
done

if ((${#MISSING[@]})); then
    echo "[chezmoi] Missing required tools: ${MISSING[*]}" >&2
    exit 1
fi

if command -v docker >/dev/null 2>&1; then
    if ! groups | grep -qw docker; then
        echo "[chezmoi] WARNING: Current user $(whoami) is not in the docker group." >&2
        echo "[chezmoi] Docker services may not work. Run: sudo usermod -aG docker $(whoami) && newgrp docker" >&2
        # Don't exit - allow init to continue, just warn
    fi
fi

exit 0
