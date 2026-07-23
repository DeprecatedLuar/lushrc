#!/usr/bin/env bash
# lsh add — save an SSH config entry to ~/.ssh/config.d/lsh

lsh_add() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: lsh add <name> <user@host[:port]> [-p port]" >&2
        return 1
    fi

    local NAME="$1" CONN="$2"
    shift 2

    # Parse port from -p flag or :port suffix
    local PORT=""
    if [[ "$1" == "-p" && -n "$2" ]]; then
        PORT="$2"
    elif [[ "$CONN" =~ :([0-9]+)$ ]]; then
        PORT="${BASH_REMATCH[1]}"
        CONN="${CONN%:*}"
    fi

    # Parse user@host
    local USER HOST
    if [[ "$CONN" =~ ^([^@]+)@(.+)$ ]]; then
        USER="${BASH_REMATCH[1]}"
        HOST="${BASH_REMATCH[2]}"
    else
        echo "lsh: invalid format, expected user@host[:port]" >&2
        return 1
    fi

    # Ensure ~/.ssh/config.d/ exists
    mkdir -p ~/.ssh/config.d
    chmod 700 ~/.ssh/config.d

    # Ensure Include directive exists in ~/.ssh/config
    local SSH_CONFIG="$HOME/.ssh/config"
    if [[ ! -f "$SSH_CONFIG" ]]; then
        echo "Include ~/.ssh/config.d/*" > "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    elif ! grep -q "^Include.*config\.d/\*" "$SSH_CONFIG"; then
        # Prepend Include directive
        local TMP
        TMP=$(mktemp)
        echo "Include ~/.ssh/config.d/*" > "$TMP"
        cat "$SSH_CONFIG" >> "$TMP"
        mv "$TMP" "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    fi

    # Append to ~/.ssh/config.d/lsh
    local LSH_CONFIG="$HOME/.ssh/config.d/lsh"
    {
        echo ""
        echo "Host $NAME"
        echo "    HostName $HOST"
        echo "    User $USER"
        [[ -n "$PORT" ]] && echo "    Port $PORT"
    } >> "$LSH_CONFIG"
    chmod 600 "$LSH_CONFIG"

    echo "Added: ssh $NAME → $USER@$HOST${PORT:+:$PORT}"
}
