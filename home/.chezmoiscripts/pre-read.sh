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
        echo "[chezmoi] Current user $(whoami) must be in the docker group before applying templates." >&2
        exit 1
    fi
fi

exit 0
