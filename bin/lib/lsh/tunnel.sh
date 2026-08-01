#!/usr/bin/env bash
# lsh tunnel — open SSH local port forward(s)
#   lsh tunnel [-d] <host> <port>[,<port>|<local>:<remote>...]
#
# Depends on: REAL_SSH (array), expand_local_ip (net.sh) — both set up by bin/lsh
# before this is called.

_lsh_tunnel_port_in_use() {
    (: < "/dev/tcp/127.0.0.1/$1") &>/dev/null
}

lsh_tunnel() {
    local BG=false
    if [[ "$1" == "-d" ]]; then
        BG=true
        shift
    fi

    if [[ $# -lt 2 ]]; then
        echo "Usage: lsh tunnel [-d] <host> <port>[,<port>|<local>:<remote>...]" >&2
        return 1
    fi

    local HOST="$1" SPEC_LIST="$2"

    # .N / user@.N subnet shorthand, same as plain `lsh`
    if [[ "$HOST" =~ ^([^@]+@)?(\.[0-9]+)$ ]]; then
        local prefix="${BASH_REMATCH[1]}" expanded
        expanded=$(expand_local_ip "${BASH_REMATCH[2]}") || return 1
        HOST="${prefix}${expanded}"
    fi

    local -a FWD=()
    local spec local_port remote_port
    IFS=',' read -ra SPECS <<< "$SPEC_LIST"
    for spec in "${SPECS[@]}"; do
        if [[ "$spec" =~ ^([0-9]+):([0-9]+)$ ]]; then
            local_port="${BASH_REMATCH[1]}"
            remote_port="${BASH_REMATCH[2]}"
        elif [[ "$spec" =~ ^[0-9]+$ ]]; then
            local_port="$spec"
            remote_port="$spec"
        else
            echo "lsh tunnel: invalid port spec '$spec' (expected port or local:remote)" >&2
            return 1
        fi

        if _lsh_tunnel_port_in_use "$local_port"; then
            local hint_flag=""
            $BG && hint_flag="-d "
            echo "lsh tunnel: local port $local_port already in use — try a different one, e.g. lsh tunnel ${hint_flag}${HOST} $((local_port + 1)):${remote_port}" >&2
            return 1
        fi

        FWD+=(-L "${local_port}:localhost:${remote_port}")
    done

    if $BG; then
        "${REAL_SSH[@]}" -fN "${FWD[@]}" "$HOST"
    else
        exec "${REAL_SSH[@]}" -N "${FWD[@]}" "$HOST"
    fi
}
