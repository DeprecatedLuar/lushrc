#!/usr/bin/env bash
# expose-bootstrap.sh — one-liner remote bootstrap for `lsh hack expose`.
#
# Shared by the machine owner as:
#   bash <(curl -fsSL https://raw.githubusercontent.com/DeprecatedLuar/lushrc/main/bin/lib/lsh/expose-bootstrap.sh)
#
# The `bash <(curl ...)` form (not `curl ... | bash`) is deliberate: it keeps stdin on the
# terminal so the consent prompt and sudo can read from it.
#
# Runs on a fresh Linux box (WSL guest, container, VM) with no lushrc: prepares sshd, authorises
# the owner's GitHub keys, pulls lsh wholesale into a temp dir, and runs `hack expose` from there.
# The Cloudflare tunnel is outbound, so no WSL/LAN networking config is needed.
#
# This is an orchestrator: it only sequences the steps below. The tunnel logic lives untouched in
# bin/lib/lsh/hack.sh + system/shared/cloudflare-tunnel.sh, reached via main.sh in the copied tree.

set -euo pipefail

# --- constants -------------------------------------------------------------------------------
OWNER="DeprecatedLuar"
REPO="lushrc"
KEYS_URL="https://github.com/${OWNER}.keys"
TARBALL_URL="https://codeload.github.com/${OWNER}/${REPO}/tar.gz/refs/heads/main"
SSH_PORT=22

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

TMP=""
cleanup() { [[ -n "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

die() { echo "expose-bootstrap: $*" >&2; exit 1; }

# --- step 1: announce + consent -------------------------------------------------------------
consent() {
    cat >&2 <<EOF

This sets up temporary remote access to THIS machine for ${OWNER}. It will:
  · install openssh-server + openssh-client (needs sudo)
  · authorise ${OWNER}'s public keys from ${KEYS_URL}
  · start sshd on port ${SSH_PORT}
  · open an OUTBOUND Cloudflare tunnel and print a connect line

Nothing is installed permanently; the tunnel closes when you press Ctrl-C.

EOF
    if [[ -t 0 ]]; then
        local reply=""
        read -r -p "Proceed? [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]] || die "cancelled"
    else
        echo "(non-interactive stdin — proceeding)" >&2
    fi
}

# --- step 2: ensure sshd installed ----------------------------------------------------------
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

# --- step 3: prepare sshd (host keys, config) -----------------------------------------------
prepare_sshd() {
    $SUDO ssh-keygen -A >/dev/null 2>&1 || true    # generate host keys if missing
    $SUDO mkdir -p /run/sshd                        # privsep dir some distros need

    # Ensure pubkey auth is on; append only if there's no active directive already.
    if ! $SUDO grep -Eq '^[[:space:]]*PubkeyAuthentication[[:space:]]+yes' /etc/ssh/sshd_config 2>/dev/null; then
        echo 'PubkeyAuthentication yes' | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
    fi
}

# --- step 4: authorise the owner's GitHub keys ----------------------------------------------
authorize_keys() {
    local ak="$HOME/.ssh/authorized_keys"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    touch "$ak"; chmod 600 "$ak"

    local keys
    keys=$(curl -fsSL "$KEYS_URL") || die "could not fetch keys from $KEYS_URL"
    [[ -n "$keys" ]] || die "no public keys published at $KEYS_URL"

    local added=0 line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! grep -Fxq "$line" "$ak"; then
            echo "$line" >> "$ak"
            added=$((added + 1))
        fi
    done <<< "$keys"
    echo "· authorised keys (${added} new)" >&2
}

# --- step 5: start sshd (no-systemd-aware) --------------------------------------------------
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

# --- step 6: fetch lsh wholesale and expose -------------------------------------------------
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
consent
install_openssh
prepare_sshd
authorize_keys
start_sshd
expose "$@"
