#!/bin/bash
# Shared utilities for Specus infrastructure scripts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

require_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root"
        exit 1
    fi
}

confirm_or_exit() {
    local prompt="${1:-Proceed?}"
    if [ "${AUTO_APPROVE:-}" = "true" ]; then
        return 0
    fi
    read -p "$prompt (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_warn "Cancelled"
        exit 0
    fi
}

validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9._:/-]+$ ]]; then
        log_error "Invalid URL: $url"
        exit 1
    fi
}

validate_alphanumeric() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid $label: $value (use only alphanumeric, hyphens, underscores)"
        exit 1
    fi
}
