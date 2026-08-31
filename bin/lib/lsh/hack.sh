#!/usr/bin/env bash
# lsh hack — temporary SSH access over a Cloudflare Quick Tunnel
#   lsh hack expose [port]        expose local sshd (or [port]) to the internet
#   lsh hack connect <line>       connect using a line printed by `expose`
#
# shared: net.sh cloudflare-tunnel.sh
#
# Depends on: SYSDIR (set up by bin/lsh before this is sourced).

_LSH_HACK_TUNNEL_PID_FILE="${TMPDIR:-/tmp}/lsh-hack-tunnel.pid"

_lsh_hack_port_listening() {
    (: < "/dev/tcp/127.0.0.1/$1") &>/dev/null
}

# Auto-detect the sshd listening port from sshd_config; default to 22.
_lsh_hack_detect_ssh_port() {
    local port
    port=$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null \
        | awk '{print $2}' | head -1)
    echo "${port:-22}"
}

lsh_hack_expose() {
    source "$SYSDIR/shared/cloudflare-tunnel.sh"

    local port="$1"
    if [[ -z "$port" ]]; then
        port=$(_lsh_hack_detect_ssh_port)
    elif [[ ! "$port" =~ ^[0-9]+$ ]]; then
        echo "lsh hack expose: invalid port '$port'" >&2
        return 1
    fi

    if ! _lsh_hack_port_listening "$port"; then
        echo "lsh hack expose: nothing is listening on port $port (is sshd running?)" >&2
        return 1
    fi

    local cleanup_done=false
    _lsh_hack_expose_cleanup() {
        $cleanup_done && return
        cleanup_done=true
        stop_quick_tunnel "$_LSH_HACK_TUNNEL_PID_FILE"
    }
    trap _lsh_hack_expose_cleanup EXIT INT TERM

    echo "  · starting cloudflare tunnel for port $port..." >&2
    local public_url
    public_url=$(start_quick_tunnel "ssh://localhost:$port" "$_LSH_HACK_TUNNEL_PID_FILE") || {
        echo "error: tunnel failed to start" >&2
        return 1
    }

    local user host
    user="${SUDO_USER:-$(whoami)}"
    host="$(hostname)"

    local line="lsh hack connect ${user}@${host}@${public_url}"
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        printf '\033[34m%s\033[0m\n' "$line"
    else
        printf '%s\n' "$line"
    fi

    # Block until interrupted, like `serve`. A single blocking sleep (rather
    # than a loop) is required so Ctrl-C ends the function instead of just
    # killing this one sleep and letting the next iteration respawn it.
    sleep infinity
}

lsh_hack_connect() {
    source "$SYSDIR/shared/cloudflare-tunnel.sh"

    local line="$1"
    if [[ -z "$line" ]]; then
        echo "Usage: lsh hack connect <user>@<host>@<tunnel-url>" >&2
        return 1
    fi

    if [[ ! "$line" =~ ^([^@]+)@([^@]+)@(https://[a-z0-9-]+\.trycloudflare\.com)$ ]]; then
        echo "lsh hack connect: unrecognized line, expected <user>@<host>@<tunnel-url>" >&2
        return 1
    fi

    local user="${BASH_REMATCH[1]}" host="${BASH_REMATCH[2]}" tunnel_url="${BASH_REMATCH[3]}"
    local tunnel_host="${tunnel_url#https://}"

    ensure_cloudflared || return 1

    exec ssh -o "ProxyCommand=cloudflared access ssh --hostname ${tunnel_host}" "${user}@${host}"
}

lsh_hack() {
    case "$1" in
        expose)
            shift
            lsh_hack_expose "$@"
            ;;
        connect)
            shift
            lsh_hack_connect "$@"
            ;;
        *)
            echo "Usage: lsh hack expose [port] | lsh hack connect <line>" >&2
            return 1
            ;;
    esac
}
