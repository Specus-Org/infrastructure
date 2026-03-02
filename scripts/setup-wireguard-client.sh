#!/bin/bash

# WireGuard Client Setup Script for Specus Infrastructure
# Installs WireGuard client and connects to the Specus VPN
# Supports: Ubuntu/Debian
# Usage: sudo ./setup-wireguard-client.sh <server-name> <config-url>

set -euo pipefail

source "$(dirname "$0")/common.sh"

CURRENT_STEP=""
trap 'if [ -n "$CURRENT_STEP" ]; then log_error "Failed during: $CURRENT_STEP"; fi' ERR

SERVER_NAME="${1:-}"
CONFIG_URL="${2:-}"

if [ -z "$SERVER_NAME" ] || [ -z "$CONFIG_URL" ]; then
    log_error "Usage: $0 <server-name> <config-url>"
    log_error "Example: $0 specus-vps 'https://vpn.specus.id/cnf/abc123'"
    exit 1
fi

validate_alphanumeric "$SERVER_NAME" "server-name"
validate_url "$CONFIG_URL"
require_root

log_info "========================================="
log_info "WireGuard Client Setup: $SERVER_NAME"
log_info "========================================="

# =============================================================================
# Install WireGuard
# =============================================================================
CURRENT_STEP="system package update"
log_step "Updating package index..."
apt update

CURRENT_STEP="WireGuard installation"
log_step "Installing WireGuard and resolvconf..."
apt install -y wireguard resolvconf

# =============================================================================
# Download configuration from wg-easy
# =============================================================================
CURRENT_STEP="configuration download"
log_step "Downloading WireGuard configuration from wg-easy..."

# Assumes the config URL is accessed over a trusted channel (VPN or verified HTTPS)
curl -L -o /etc/wireguard/wg0.conf "$CONFIG_URL"

if [ ! -f /etc/wireguard/wg0.conf ]; then
    log_error "Failed to download WireGuard configuration"
    exit 1
fi

if grep -q "DOCTYPE\|<html" /etc/wireguard/wg0.conf; then
    log_error "Downloaded file is HTML, not a WireGuard configuration"
    log_error "The one-time URL may have expired or been already used"
    log_error "Generate a new config URL from wg-easy UI"
    rm /etc/wireguard/wg0.conf
    exit 1
fi

if ! grep -q "\[Interface\]" /etc/wireguard/wg0.conf; then
    log_error "Downloaded file is not a valid WireGuard configuration"
    head -5 /etc/wireguard/wg0.conf
    rm /etc/wireguard/wg0.conf
    exit 1
fi

chmod 600 /etc/wireguard/wg0.conf
log_info "Configuration saved and secured"

# =============================================================================
# Enable IP forwarding
# =============================================================================
CURRENT_STEP="IP forwarding"
log_step "Enabling IP forwarding..."

cat > /etc/sysctl.d/99-wireguard.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system

CURRENT_STEP="kernel module"
log_step "Loading WireGuard kernel module..."
if ! lsmod | grep -q wireguard; then
    modprobe wireguard || log_warn "Failed to load module (may be built into kernel)"
fi

# =============================================================================
# Enable and start WireGuard
# =============================================================================
CURRENT_STEP="WireGuard service"
log_step "Enabling WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

sleep 2

CURRENT_STEP="connection verification"
log_step "Verifying WireGuard connection..."
if wg show wg0 &> /dev/null; then
    log_info "WireGuard interface is up"
    wg show wg0
else
    log_error "WireGuard interface failed to start"
    exit 1
fi

log_step "Testing connectivity to VPN gateway (10.8.0.1)..."
if ping -c 3 10.8.0.1 &> /dev/null; then
    log_info "Successfully connected to VPN network!"
else
    log_warn "Cannot ping VPN gateway. Check firewall rules."
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
log_info "========================================="
log_info "WireGuard Client Setup Complete: $SERVER_NAME"
log_info "========================================="
log_info "  Interface: wg0"
log_info "  Config: /etc/wireguard/wg0.conf"
echo ""
log_info "Interface status:"
ip addr show wg0
echo ""
log_info "Commands:"
log_info "  View logs: journalctl -u wg-quick@wg0 -f"
log_info "  Restart:   systemctl restart wg-quick@wg0"
log_info "  Status:    wg show"
