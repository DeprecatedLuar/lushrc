#!/usr/bin/env bash
# expose-bootstrap.sh — one-liner remote bootstrap for `lsh hack expose`.
#
# Shared by the machine owner as:
#   bash <(curl -fsSL https://raw.githubusercontent.com/DeprecatedLuar/lushrc/main/bin/lib/lsh/expose-bootstrap.sh)
#
# The `bash <(curl ...)` form (not `curl ... | bash`) is deliberate: it keeps stdin on the
# terminal so sudo can prompt for a password if needed.
#
# Runs on a fresh Linux box (WSL guest, container, VM) with no lushrc: prepares sshd (installing
# it and enabling password auth if needed — the connecting side just uses the user's own login
# password, nothing generated), pulls lsh wholesale into a temp dir, and runs `hack expose` from
# there. The Cloudflare tunnel is outbound, so no WSL/LAN networking config is needed.
#
# This is an orchestrator: it only sequences the steps below. The tunnel logic lives untouched in
# bin/lib/lsh/hack.sh + system/shared/cloudflare-tunnel.sh, reached via main.sh in the copied tree.

set -euo pipefail

# --- constants -------------------------------------------------------------------------------
REPO="DeprecatedLuar/lushrc"
TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/main"
SSH_PORT=22

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

TMP=""
cleanup() { [[ -n "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

die() { echo "expose-bootstrap: $*" >&2; exit 1; }

# --- step 1: ensure sshd installed ----------------------------------------------------------
install_openssh() {
    command -v sshd >/dev/null 2>&1 && command -v ssh >/dev/null 2>&1 && return 0

    echo "· installing openssh..." >&2
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq openssh-server openssh-client curl ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y openssh-server openssh-clients curl
    elif command -v yum >/dev/null 2>&1; then
        $SUDO yum install -y openssh-server openssh-clients curl
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm openssh curl
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache openssh openssh-client curl
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper install -y openssh curl
    else
        die "no supported package manager found (apt/dnf/yum/pacman/apk/zypper)"
    fi

    command -v sshd >/dev/null 2>&1 || die "sshd not found after install"
    command -v ssh  >/dev/null 2>&1 || die "ssh client not found after install (lsh needs it)"
}

# --- step 2: prepare sshd (host keys, password auth) ----------------------------------------
prepare_sshd() {
    $SUDO ssh-keygen -A >/dev/null 2>&1 || true    # generate host keys if missing
    $SUDO mkdir -p /run/sshd                        # privsep dir some distros need

    # Force password auth on, in case the distro default disables it. The user's own login
    # password is what's used to connect — nothing generated or stored here.
    if $SUDO grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config 2>/dev/null; then
        $SUDO sed -i 's/^[[:space:]]*PasswordAuthentication[[:space:]]\+no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    elif ! $SUDO grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+yes' /etc/ssh/sshd_config 2>/dev/null; then
        echo 'PasswordAuthentication yes' | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
    fi
}

# --- step 3: start sshd (no-systemd-aware) --------------------------------------------------
start_sshd() {
    port_listening && return 0

    if [[ -d /run/systemd/system ]]; then
        $SUDO systemctl enable --now ssh 2>/dev/null \
            || $SUDO systemctl enable --now sshd 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        $SUDO service ssh start 2>/dev/null \
            || $SUDO service sshd start 2>/dev/null || true
    fi

    port_listening && return 0
    $SUDO "$(command -v sshd)"          # last resort: launch the daemon directly

    local waited=0
    while ! port_listening; do
        sleep 0.5; waited=$((waited + 1))
        [[ $waited -ge 20 ]] && die "sshd did not come up on port ${SSH_PORT}"
    done
}

port_listening() { (: < "/dev/tcp/127.0.0.1/${SSH_PORT}") >/dev/null 2>&1; }

# --- step 4: fetch lsh wholesale and expose -------------------------------------------------
expose() {
    TMP=$(mktemp -d)
    echo "· fetching lsh..." >&2
    curl -fsSL "$TARBALL_URL" | tar xz -C "$TMP" || die "failed to fetch/extract lsh tarball"

    local main
    main=$(echo "$TMP"/*/bin/lib/lsh/main.sh)
    [[ -f "$main" ]] || die "lsh main.sh not found in tarball"

    # hack expose auto-detects the sshd port, starts the tunnel, prints the connect line, blocks.
    LSH_INTERACTIVE_SHELL= bash "$main" hack expose "$@"
}

# --- orchestrate ----------------------------------------------------------------------------
install_openssh
prepare_sshd
start_sshd
expose "$@"
