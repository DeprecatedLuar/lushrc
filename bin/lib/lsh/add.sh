#!/usr/bin/env bash
# lsh add — save an SSH config entry to ~/.ssh/config.d/lsh
#   lsh add                              interactive: opens $EDITOR on a key=value scratch file
#   lsh add <name>                       interactive: name prefilled, opens $EDITOR for the rest
#   lsh add <name> <[user@]host[:port]> [-p port]
#                                         direct: creates immediately, no editor
#                                         (user and port are optional, host is not)

lsh_add() {
    local NAME="${1:-}"
    [[ $# -ge 1 ]] && shift

    local HOST="" USER="" PORT=""

    if [[ $# -gt 0 ]]; then
        # Direct mode — connection info given, create immediately
        local CONN="$1"
        shift

        if [[ "$1" == "-p" && -n "$2" ]]; then
            PORT="$2"
        elif [[ "$CONN" =~ :([0-9]+)$ ]]; then
            PORT="${BASH_REMATCH[1]}"
            CONN="${CONN%:*}"
        fi

        if [[ "$CONN" =~ ^([^@]+)@(.+)$ ]]; then
            USER="${BASH_REMATCH[1]}"
            HOST="${BASH_REMATCH[2]}"
        else
            HOST="$CONN"
        fi

        [[ -z "$NAME" || -z "$HOST" ]] && { echo "lsh add: name and host required" >&2; return 1; }
    else
        # Interactive mode — key=value scratch file in $EDITOR, name prefilled if given
        local SCRATCH
        SCRATCH=$(mktemp)
        {
            echo "name=$NAME"
            echo "host="
            echo "user="
            echo "port=22"
        } > "$SCRATCH"

        "${EDITOR:-vi}" "$SCRATCH"

        local NEW_NAME="" NEW_HOST="" NEW_USER="" NEW_PORT=""
        while IFS='=' read -r key val; do
            case "$key" in
                name) NEW_NAME="$val" ;;
                host) NEW_HOST="$val" ;;
                user) NEW_USER="$val" ;;
                port) NEW_PORT="$val" ;;
            esac
        done < "$SCRATCH"
        rm -f "$SCRATCH"

        [[ -z "$NEW_NAME" || -z "$NEW_HOST" ]] && { echo "lsh add: name and host are required, aborting" >&2; return 1; }

        NAME="$NEW_NAME" HOST="$NEW_HOST" USER="$NEW_USER" PORT="$NEW_PORT"
    fi

    PORT="${PORT:-22}"

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
        [[ -n "$USER" ]] && echo "    User $USER"
        [[ -n "$PORT" ]] && echo "    Port $PORT"
    } >> "$LSH_CONFIG"
    chmod 600 "$LSH_CONFIG"

    lsh_status_line + "$NAME"
}
