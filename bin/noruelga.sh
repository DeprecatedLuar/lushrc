#!/usr/bin/env bash

# Deploy noruelga SSH key for user and root access
# - Sets up user SSH (symlink + authorized_keys)
# - Configures sshd for key-only root login (optional)
# - Deploys public key to /root/.ssh/authorized_keys

set -e

SSHD_CONFIG="/etc/ssh/sshd_config"
PUBKEY="$BASHRC/modules/universal/.noruelga.pub"

# User SSH setup
mkdir -p "$HOME/.ssh"
ln -sf "$PUBKEY" "$HOME/.ssh/noruelga.pub"
if ! grep -qF "$(cat "$PUBKEY")" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    cat "$PUBKEY" >> "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo "Added key to user authorized_keys"
else
    echo "User authorized_keys already has key"
fi

# Check current sshd PermitRootLogin setting
current=$(grep -E "^#?PermitRootLogin" "$SSHD_CONFIG" 2>/dev/null | tail -1 || echo "")
sshd_changed=false

if [[ "$current" == "PermitRootLogin prohibit-password" ]]; then
    echo "sshd already configured for key-only root login"
else
    read -p "Disable root password login? (key-only) [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
        sshd_changed=true
        echo "Configured sshd for key-only root login"
    else
        echo "Skipped sshd config (root password login unchanged)"
    fi
fi

# Deploy key to root
sudo mkdir -p /root/.ssh
sudo cp "$PUBKEY" /root/.ssh/authorized_keys
sudo chmod 700 /root/.ssh
sudo chmod 600 /root/.ssh/authorized_keys
echo "Deployed key to /root/.ssh/authorized_keys"

# Restart sshd only if config changed
if [[ "$sshd_changed" == true ]]; then
    sudo systemctl restart sshd
    echo "Restarted sshd"
fi

echo "Done. Root SSH access enabled with key only."
