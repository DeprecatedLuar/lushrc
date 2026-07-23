#!/usr/bin/env bash
# lsh unlock — send SSH public key(s) to a host for password-free access
# Requires LSH_SELF (path to the lsh binary) to re-invoke for .N/--password support

lsh_unlock() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: lsh unlock <user@host[:port]> [keyfile] [--all]" >&2
        echo "  keyfile is looked up in ~/.ssh/public/<keyfile>.pub" >&2
        echo "  Auto-detects the only key in ~/.ssh/public if none given" >&2
        return 1
    fi

    local PUBDIR="$HOME/.ssh/public"
    local HOST_ARG="$1" KEYNAME="" SEND_ALL=false
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                SEND_ALL=true
                shift
                ;;
            *)
                KEYNAME="$1"
                shift
                ;;
        esac
    done

    # Resolve a key name to an actual .pub path in $PUBDIR
    _resolve_key() {
        local name="$1"
        if [[ -f "$PUBDIR/$name" ]]; then
            echo "$PUBDIR/$name"
        elif [[ -f "$PUBDIR/$name.pub" ]]; then
            echo "$PUBDIR/$name.pub"
        elif [[ -f "$name" ]]; then
            echo "$name"
        fi
    }

    # Determine which key(s) to send
    local KEYS=()
    if $SEND_ALL; then
        mapfile -t KEYS < <(find "$PUBDIR" -maxdepth 1 -name "*.pub" -type f 2>/dev/null)
        [[ ${#KEYS[@]} -eq 0 ]] && { echo "lsh unlock: no public keys found in $PUBDIR/" >&2; return 1; }
    elif [[ -n "$KEYNAME" ]]; then
        local resolved
        resolved="$(_resolve_key "$KEYNAME")"
        [[ -z "$resolved" ]] && { echo "lsh unlock: key not found: $KEYNAME (looked in $PUBDIR/)" >&2; return 1; }
        KEYS=("$resolved")
    else
        # Auto-detect: only key in $PUBDIR, else fall back to legacy id_ed25519 > id_rsa
        mapfile -t KEYS < <(find "$PUBDIR" -maxdepth 1 -name "*.pub" -type f 2>/dev/null)
        if [[ ${#KEYS[@]} -gt 1 ]]; then
            echo "lsh unlock: multiple keys in $PUBDIR/, specify one: ${KEYS[*]##*/}" >&2
            return 1
        elif [[ ${#KEYS[@]} -eq 0 ]]; then
            if [[ -f ~/.ssh/id_ed25519.pub ]]; then
                KEYS=(~/.ssh/id_ed25519.pub)
            elif [[ -f ~/.ssh/id_rsa.pub ]]; then
                KEYS=(~/.ssh/id_rsa.pub)
            else
                echo "lsh unlock: no key found in $PUBDIR/ or ~/.ssh/" >&2
                return 1
            fi
        fi
    fi

    # Read key contents
    local KEY_DATA="" key
    for key in "${KEYS[@]}"; do
        KEY_DATA+="$(cat "$key")"$'\n'
    done

    # Send keys via SSH — re-invoke lsh itself for .N expansion and --password support
    "$LSH_SELF" "$HOST_ARG" "bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'" <<< "$KEY_DATA"

    if [[ $? -eq 0 ]]; then
        echo "✓ Unlocked: ${KEYS[*]##*/} → $HOST_ARG"
    else
        echo "✗ Failed to unlock $HOST_ARG" >&2
        return 1
    fi
}
