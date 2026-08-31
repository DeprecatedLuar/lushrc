#!/usr/bin/env bash
# lsh tunnel — open SSH local port forward(s)
#   lsh tunnel [-d] <host> <port>[,<port>|<local>:<remote>...]
#
# Depends on: REAL_SSH (array), expand_local_ip (net.sh) — both set up by bin/lsh
# before this is called.
# shared: spinner.sh

source "$SYSDIR/shared/spinner.sh"

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

    local -a FWD=() LOCAL_PORTS=() REMOTE_PORTS=()
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
        LOCAL_PORTS+=("$local_port")
        REMOTE_PORTS+=("$remote_port")
    done

    local i
    echo >&2
    for i in "${!LOCAL_PORTS[@]}"; do
        printf 'localhost:%s → %s:%s\n' "${LOCAL_PORTS[$i]}" "$HOST" "${REMOTE_PORTS[$i]}" >&2
    done

    # -o ControlMaster=no/ControlPath=none: never piggyback on a shared
    # connection. A tunnel must own its process so it actually blocks (or
    # backgrounds) on its own — reusing a master's socket would let the
    # master silently own the forward instead, making -N/-fN return with
    # nothing left for this process to hold open.
    local -a NO_SHARE=(-o ControlMaster=no -o ControlPath=none)

    if $BG; then
        "${REAL_SSH[@]}" "${NO_SHARE[@]}" -fN "${FWD[@]}" "$HOST"
    else
        "${REAL_SSH[@]}" "${NO_SHARE[@]}" -N "${FWD[@]}" "$HOST" &
        local ssh_pid=$!
        spin "tunnel active" "$ssh_pid"
        wait "$ssh_pid"
    fi
}
