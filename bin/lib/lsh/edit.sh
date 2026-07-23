#!/usr/bin/env bash
# lsh edit — edit an existing SSH config entry in ~/.ssh/config.d/lsh
#   lsh edit <name>                              interactive: opens $EDITOR on a key=value scratch file
#   lsh edit <name> <user@host[:port]> [-p port]  inline: same syntax as `lsh add`, no editor

lsh_edit() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: lsh edit <name> [user@host[:port]] [-p port]" >&2
        return 1
    fi

    local NAME="$1"
    shift
    local LSH_CONFIG="$HOME/.ssh/config.d/lsh"

    [[ -f "$LSH_CONFIG" ]] || { echo "lsh edit: no entries found ($LSH_CONFIG missing)" >&2; return 1; }

    # Confirm the entry exists, and grab current values for the interactive scratch file
    local HOSTNAME="" USERVAL="" PORT=""
    local found=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$NAME" ]]; then
                found=true
            elif $found; then
                break
            fi
            continue
        fi
        $found || continue
        [[ "$line" =~ ^[[:space:]]*[Hh]ost[Nn]ame[[:space:]]+(.+)$ ]] && HOSTNAME="${BASH_REMATCH[1]}"
        [[ "$line" =~ ^[[:space:]]*[Uu]ser[[:space:]]+(.+)$ ]] && USERVAL="${BASH_REMATCH[1]}"
        [[ "$line" =~ ^[[:space:]]*[Pp]ort[[:space:]]+(.+)$ ]] && PORT="${BASH_REMATCH[1]}"
    done < "$LSH_CONFIG"

    $found || { echo "lsh edit: no entry named '$NAME' in $LSH_CONFIG" >&2; return 1; }

    local NEW_NAME="$NAME" NEW_HOST="" NEW_USER="" NEW_PORT=""

    if [[ $# -ge 1 ]]; then
        # Inline mode — same syntax as `lsh add`
        local CONN="$1"
        shift

        if [[ "$1" == "-p" && -n "$2" ]]; then
            NEW_PORT="$2"
        elif [[ "$CONN" =~ :([0-9]+)$ ]]; then
            NEW_PORT="${BASH_REMATCH[1]}"
            CONN="${CONN%:*}"
        fi

        if [[ "$CONN" =~ ^([^@]+)@(.+)$ ]]; then
            NEW_USER="${BASH_REMATCH[1]}"
            NEW_HOST="${BASH_REMATCH[2]}"
        else
            echo "lsh: invalid format, expected user@host[:port]" >&2
            return 1
        fi
    else
        # Interactive mode — key=value scratch file in $EDITOR
        local SCRATCH
        SCRATCH=$(mktemp)
        {
            echo "name=$NAME"
            echo "host=$HOSTNAME"
            echo "user=$USERVAL"
            echo "port=$PORT"
        } > "$SCRATCH"

        "${EDITOR:-vi}" "$SCRATCH"

        while IFS='=' read -r key val; do
            case "$key" in
                name) NEW_NAME="$val" ;;
                host) NEW_HOST="$val" ;;
                user) NEW_USER="$val" ;;
                port) NEW_PORT="$val" ;;
            esac
        done < "$SCRATCH"
        rm -f "$SCRATCH"
    fi

    [[ -z "$NEW_NAME" || -z "$NEW_HOST" ]] && { echo "lsh edit: name and host are required, aborting" >&2; return 1; }

    # Rewrite the Host block in place
    local TMP
    TMP=$(mktemp)
    local in_block=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$NAME" ]]; then
                in_block=true
                {
                    echo "Host $NEW_NAME"
                    echo "    HostName $NEW_HOST"
                    [[ -n "$NEW_USER" ]] && echo "    User $NEW_USER"
                    [[ -n "$NEW_PORT" ]] && echo "    Port $NEW_PORT"
                    echo ""
                } >> "$TMP"
                continue
            else
                in_block=false
            fi
        fi
        $in_block && continue
        echo "$line" >> "$TMP"
    done < "$LSH_CONFIG"

    mv "$TMP" "$LSH_CONFIG"
    chmod 600 "$LSH_CONFIG"

    echo "Updated: ssh $NEW_NAME → ${NEW_USER:+$NEW_USER@}$NEW_HOST${NEW_PORT:+:$NEW_PORT}"
}
