#!/bin/bash

# SSH Hardening Script for Specus Infrastructure
# Hardens SSH configuration for security best practices
# Supports: Ubuntu/Debian
# Run this on the server after initial setup

set -euo pipefail
source "$(dirname "$0")/common.sh"

# Configuration
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
ADMIN_USER="${ADMIN_USER:-devops}"
SSH_PORT="${SSH_PORT:-22}"

trap 'if [ $? -ne 0 ] && [ -f "${SSHD_BACKUP:-}" ]; then
    cp "$SSHD_BACKUP" "$SSHD_CONFIG"
    log_error "Failed. Backup restored to $SSHD_CONFIG"
fi' EXIT

require_root

log_info "========================================="
log_info "SSH Hardening Script for Specus Infrastructure"
log_info "========================================="
echo ""
log_info "This script will:"
log_info "  1. Create admin user ($ADMIN_USER) with sudo privileges"
log_info "  2. Allow root SSH login with SSH keys only (no password)"
log_info "  3. Disable password authentication for all users"
log_info "  4. Enable SSH key-only authentication"
log_info "  5. Install and configure fail2ban"
echo ""
log_info "Admin user: $ADMIN_USER"
log_info "SSH port: $SSH_PORT"
echo ""

confirm_or_exit "Proceed with SSH hardening?"

# =============================================================================
# Backup SSH config
# =============================================================================
log_step "Backing up current SSH configuration..."
cp "$SSHD_CONFIG" "$SSHD_BACKUP"
log_info "Backup saved to: $SSHD_BACKUP"

# =============================================================================
# Create admin user
# =============================================================================
log_step "Checking admin user..."

if id "$ADMIN_USER" &>/dev/null; then
    log_info "User $ADMIN_USER already exists"
else
    log_info "Creating admin user: $ADMIN_USER"
    adduser --disabled-password --gecos "" "$ADMIN_USER"
    usermod -aG sudo "$ADMIN_USER"
    log_info "User $ADMIN_USER created and added to sudo group"
fi

# Configure passwordless sudo (required by Dokploy)
SUDOERS_FILE="/etc/sudoers.d/$ADMIN_USER"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
    log_info "Passwordless sudo configured for $ADMIN_USER"
else
    log_info "Sudo configuration already exists for $ADMIN_USER"
fi

# =============================================================================
# Setup SSH keys
# =============================================================================
log_step "Setting up SSH directory for $ADMIN_USER..."
mkdir -p "/home/$ADMIN_USER/.ssh"
chmod 700 "/home/$ADMIN_USER/.ssh"
touch "/home/$ADMIN_USER/.ssh/authorized_keys"
chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"

if [ ! -s "/home/$ADMIN_USER/.ssh/authorized_keys" ]; then
    log_warn "No SSH key found for $ADMIN_USER"
    log_info "Paste your SSH public key (or press Enter to skip):"
    read -p "> " SSH_KEY

    if [ -n "$SSH_KEY" ]; then
        if [[ ! "$SSH_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
            log_error "Invalid SSH key format. Key must start with ssh-rsa, ssh-ed25519, or ssh-ecdsa."
            exit 1
        fi
        echo "$SSH_KEY" >> "/home/$ADMIN_USER/.ssh/authorized_keys"
        log_info "SSH key added for $ADMIN_USER"
    else
        log_error "No SSH key added. Cannot disable password authentication safely."
        log_error "Add your key to /home/$ADMIN_USER/.ssh/authorized_keys and re-run."
        exit 1
    fi
fi

# Setup root SSH keys
log_step "Setting up root SSH authorized_keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

if [ ! -s /root/.ssh/authorized_keys ]; then
    log_warn "No SSH key found for root"
    log_info "Paste your SSH public key for root (or press Enter to skip):"
    read -p "> " ROOT_SSH_KEY

    if [ -n "$ROOT_SSH_KEY" ]; then
        if [[ ! "$ROOT_SSH_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
            log_error "Invalid SSH key format. Key must start with ssh-rsa, ssh-ed25519, or ssh-ecdsa."
            exit 1
        fi
        echo "$ROOT_SSH_KEY" >> /root/.ssh/authorized_keys
        log_info "SSH key added for root"
    else
        log_warn "Skipped adding SSH key for root"
    fi
else
    log_info "SSH key already exists for root"
fi

# =============================================================================
# Harden SSH configuration
# =============================================================================
log_step "Hardening SSH configuration..."

update_ssh_config() {
    local key=$1
    local value=$2
    sed -i "/^#*\s*$key\s/d" "$SSHD_CONFIG"
    echo "$key $value" >> "$SSHD_CONFIG"
}

update_ssh_config "Port" "$SSH_PORT"
update_ssh_config "PermitRootLogin" "prohibit-password"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "AllowUsers" "root $ADMIN_USER"
update_ssh_config "MaxAuthTries" "3"
update_ssh_config "MaxSessions" "10"
update_ssh_config "MaxStartups" "3:50:10"
update_ssh_config "LoginGraceTime" "60"
update_ssh_config "ClientAliveInterval" "300"
update_ssh_config "ClientAliveCountMax" "2"
update_ssh_config "X11Forwarding" "no"
update_ssh_config "AllowAgentForwarding" "no"
update_ssh_config "AllowTcpForwarding" "no"
update_ssh_config "LogLevel" "VERBOSE"
update_ssh_config "DebianBanner" "no"
update_ssh_config "GSSAPIAuthentication" "no"
update_ssh_config "KexAlgorithms" "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256"
update_ssh_config "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
update_ssh_config "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"

log_info "SSH configuration hardened"

# =============================================================================
# Validate SSH configuration
# =============================================================================
log_step "Validating SSH configuration..."
if sshd -t -f "$SSHD_CONFIG"; then
    log_info "SSH configuration is valid"
else
    log_error "SSH configuration is invalid! Restoring backup..."
    cp "$SSHD_BACKUP" "$SSHD_CONFIG"
    log_info "Backup restored. Check configuration manually."
    exit 1
fi

# =============================================================================
# Install fail2ban
# =============================================================================
log_step "Setting up fail2ban..."

if ! command -v fail2ban-client &> /dev/null; then
    log_info "Installing fail2ban..."
    apt update
    apt install -y fail2ban
fi

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = $SSH_PORT
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log_info "fail2ban configured and started"

# =============================================================================
# Determine SSH service name
# =============================================================================
SSH_SERVICE="sshd"
if systemctl list-unit-files | grep -q "^ssh.service"; then
    SSH_SERVICE="ssh"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
log_info "========================================="
log_info "SSH Hardening Summary"
log_info "========================================="
log_info "  Config backed up to: $SSHD_BACKUP"
log_info "  Admin user: $ADMIN_USER (passwordless sudo)"
log_info "  SSH port: $SSH_PORT"
log_info "  Root login: SSH KEY ONLY"
log_info "  Password auth: DISABLED"
log_info "  Public key auth: ENABLED"
log_info "  Allowed users: root, $ADMIN_USER"
log_info "  Max auth tries: 3"
log_info "  fail2ban: ENABLED (3 failures = 1hr ban)"
log_info "  Crypto: curve25519, AES-256-GCM, HMAC-SHA-512"
echo ""
log_warn "========================================="
log_warn "IMPORTANT: Before closing this session!"
log_warn "========================================="
log_warn "1. Open a NEW terminal"
log_warn "2. Test SSH: ssh -p $SSH_PORT root@<server-ip>"
log_warn "3. Test SSH: ssh -p $SSH_PORT $ADMIN_USER@<server-ip>"
log_warn "4. Only then restart SSH service"
log_warn ""
log_warn "If connection fails, restore backup:"
log_warn "  sudo cp $SSHD_BACKUP $SSHD_CONFIG"
log_warn "  sudo systemctl restart $SSH_SERVICE"
log_warn "========================================="
echo ""

confirm_or_exit "Restart SSH service now?"
log_step "Restarting SSH service..."
systemctl restart "$SSH_SERVICE"
log_info "SSH service restarted"
log_info "Test your connection in a new terminal!"

echo ""
log_info "fail2ban status: sudo fail2ban-client status sshd"
