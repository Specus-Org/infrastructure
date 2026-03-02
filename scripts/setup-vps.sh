#!/bin/bash

# VPS Setup Script for Specus Infrastructure
# Run this AFTER Dokploy is installed (Docker is already available)
# Supports: Ubuntu/Debian
# Usage: sudo ./setup-vps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
SWAP_SIZE="${SWAP_SIZE:-2G}"
TIMEZONE="${TIMEZONE:-UTC}"
WG_EASY_DIR="/opt/specus/wg-easy"

CURRENT_STEP="initialization"
cleanup_on_error() {
    log_error "Setup failed during: $CURRENT_STEP"
}
trap cleanup_on_error ERR

require_root

# Validate inputs
if [[ ! "$SWAP_SIZE" =~ ^[0-9]+[GgMm]$ ]]; then
    log_error "Invalid SWAP_SIZE: $SWAP_SIZE (must match e.g. 2G, 512M)"
    exit 1
fi

if ! timedatectl list-timezones 2>/dev/null | grep -qx "$TIMEZONE"; then
    log_error "Invalid TIMEZONE: $TIMEZONE (check timedatectl list-timezones)"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Dokploy first."
    log_error "Run: curl -sSL https://dokploy.com/install.sh | sh"
    exit 1
fi

log_info "========================================="
log_info "Specus VPS Setup Script"
log_info "========================================="
echo ""
log_info "This script will:"
log_info "  1. Update system & install essential packages"
log_info "  2. Create swap file (${SWAP_SIZE})"
log_info "  3. Tune kernel parameters (sysctl)"
log_info "  4. Set timezone to ${TIMEZONE}"
log_info "  5. Enable unattended security upgrades"
log_info "  6. Configure journald log limits"
log_info "  7. Deploy wg-easy VPN server"
echo ""

confirm_or_exit "Proceed with VPS setup?"

# =============================================================================
# 1. System update & essential packages
# =============================================================================
CURRENT_STEP="system update & essential packages"
log_step "Updating system packages..."
apt update && apt upgrade -y

log_step "Installing essential packages..."
apt install -y \
    curl \
    htop \
    jq \
    dnsutils

log_info "Essential packages installed"

# =============================================================================
# 2. Swap file
# =============================================================================
CURRENT_STEP="swap file"
log_step "Configuring swap..."

if swapon --show | grep -q "/swapfile"; then
    log_info "Swap file already exists"
    swapon --show
else
    log_info "Creating ${SWAP_SIZE} swap file..."
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    log_info "Swap file created and enabled"
    swapon --show
fi

# =============================================================================
# 3. Sysctl tuning
# =============================================================================
CURRENT_STEP="sysctl tuning"
log_step "Applying kernel parameter tuning..."

cat > /etc/sysctl.d/99-specus.conf << 'EOF'
# Specus Infrastructure - Kernel Tuning
# Optimized for 4GB VPS running Docker services

# Swap behavior (prefer RAM, swap only when necessary)
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 5

# TCP keepalive (detect dead connections faster)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# TCP performance
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# IP forwarding (required for WireGuard and Docker)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

modprobe nf_conntrack 2>/dev/null || true

# Load ip6_tables module required by WireGuard (wg-quick uses ip6tables)
if ! modprobe ip6_tables 2>/dev/null; then
    log_warn "ip6_tables module not found, installing linux-modules-extra..."
    apt install -y "linux-modules-extra-$(uname -r)"
    modprobe ip6_tables
fi

sysctl --system
log_info "Kernel parameters applied"

# =============================================================================
# 4. Timezone
# =============================================================================
CURRENT_STEP="timezone"
log_step "Setting timezone to ${TIMEZONE}..."
timedatectl set-timezone "$TIMEZONE"
log_info "Timezone set to $(timedatectl show --property=Timezone --value)"

# =============================================================================
# 5. Unattended upgrades
# =============================================================================
CURRENT_STEP="unattended upgrades"
log_step "Configuring unattended security upgrades..."
apt install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades
log_info "Unattended security upgrades enabled"

# =============================================================================
# 6. Journald log limits
# =============================================================================
CURRENT_STEP="journald log limits"
log_step "Configuring journald log limits..."

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/specus.conf << 'EOF'
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=30day
EOF

systemctl restart systemd-journald
log_info "Journald configured (max 500MB, 30-day retention)"

# =============================================================================
# 7. Deploy wg-easy VPN server
# =============================================================================
CURRENT_STEP="wg-easy VPN deployment"
log_step "Deploying wg-easy VPN server..."

echo ""
log_info "wg-easy requires credentials for the admin web UI"

# Detect public IP for WireGuard endpoint
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || true)
read -p "Enter server public IP or domain [${SERVER_IP}]: " WG_HOST
WG_HOST="${WG_HOST:-$SERVER_IP}"

if [ -z "$WG_HOST" ]; then
    log_error "Server public IP/domain is required for WireGuard clients"
    exit 1
fi

read -p "Enter wg-easy admin username [admin]: " WG_USERNAME
WG_USERNAME="${WG_USERNAME:-admin}"
read -sp "Enter wg-easy admin password: " WG_PASSWORD
echo ""

if [ -z "$WG_PASSWORD" ]; then
    log_error "Password cannot be empty"
    exit 1
fi

log_info "Pulling wg-easy image (this may take a moment)..."
docker pull ghcr.io/wg-easy/wg-easy:15

mkdir -p "$WG_EASY_DIR"
mkdir -p /etc/wireguard

cp "$SCRIPT_DIR/../wg-easy/docker-compose.yml" "$WG_EASY_DIR/docker-compose.yml"

cat > "$WG_EASY_DIR/.env" << EOF
INIT_ENABLED=true
INIT_USERNAME=${WG_USERNAME}
INIT_PASSWORD=${WG_PASSWORD}
INIT_HOST=${WG_HOST}
INIT_PORT=51820
INIT_DNS=1.1.1.1
INIT_IPV4_CIDR=10.8.0.0/24
INIT_ALLOWED_IPS=10.8.0.0/24
EOF
chmod 600 "$WG_EASY_DIR/.env"
unset WG_PASSWORD

log_info "Starting wg-easy..."
docker compose -f "$WG_EASY_DIR/docker-compose.yml" up -d

sleep 5

if docker ps | grep -q wg-easy; then
    log_info "wg-easy is running"
else
    log_error "wg-easy failed to start. Check: docker logs wg-easy"
    exit 1
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
log_info "========================================="
log_info "VPS Setup Complete"
log_info "========================================="
log_info "  System packages: installed"
log_info "  Swap: ${SWAP_SIZE} enabled"
log_info "  Kernel tuning: applied"
log_info "  Timezone: ${TIMEZONE}"
log_info "  Unattended upgrades: enabled"
log_info "  Journald: 500MB max, 30-day retention"
log_info "  wg-easy: running on ports 51820/udp + 51821/tcp"
echo ""
log_info "Next steps:"
log_info "  1. Access wg-easy UI at http://<server-ip>:51821 and log in"
log_info "  2. Remove INIT_* vars from $WG_EASY_DIR/.env (credentials stored in DB after first login)"
log_info "  3. Run ./harden-ssh.sh to secure SSH access"
log_info "  4. Configure Vultr cloud firewall (see firewall/vultr/specus-vps.md)"
log_info "  5. Create VPN client configs via wg-easy UI"
echo ""
log_info "wg-easy compose location: $WG_EASY_DIR"
log_info "WireGuard configs: /etc/wireguard"
