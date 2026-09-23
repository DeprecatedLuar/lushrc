#!/usr/bin/env bash
# lsh hack — temporary SSH access over a Cloudflare Quick Tunnel
#   lsh hack expose [port]        expose local sshd (or [port]) to the internet
#   lsh hack connect <line>       connect using a line printed by `expose`
#
# shared: net.sh cloudflare-tunnel.sh
#
# Depends on SYSDIR, LSH_SELF and _RAW_SSH (set up by main.sh before this is
# sourced), so a tunnelled connection reuses the same terminal adapters as a
# plain one.

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

    local cleanup_done=false stop=false
    _lsh_hack_expose_cleanup() {
        $cleanup_done && return
        cleanup_done=true
        stop=true
        stop_quick_tunnel "$_LSH_HACK_TUNNEL_PID_FILE"
    }
    _lsh_hack_expose_interrupt() {
        printf '\npress q then enter to exit (Ctrl-C will not stop the tunnel)\n'
    }
    trap _lsh_hack_expose_cleanup EXIT TERM
    trap _lsh_hack_expose_cleanup INT

    printf 'starting cloudflare tunnel for port %s\n\n' "$port" >&2
    local public_url
    public_url=$(start_quick_tunnel "ssh://localhost:$port" "$_LSH_HACK_TUNNEL_PID_FILE") || {
        echo "error: tunnel failed to start" >&2
        return 1
    }

    local user host
    user="${SUDO_USER:-$(whoami)}"
    host="$(hostname)"

    local line="lsh hack connect ${user}@${host}@${public_url}"
    local interactive=false
    [[ -t 0 && -t 1 ]] && interactive=true
    $interactive && trap _lsh_hack_expose_interrupt INT

    if $interactive; then
        if [[ -z "${NO_COLOR:-}" ]]; then
            printf '\033[34m%s\033[0m\n\n' "$line"
        else
            printf '%s\n\n' "$line"
        fi
    else
        printf '%s\n\n' "$line"
    fi

    local can_copy=false
    $interactive && command -v wl-copy >/dev/null 2>&1 && can_copy=true
    $interactive && printf 'press q then enter to exit\n'
    $can_copy && printf 'press enter to copy\n'

    local tunnel_pid=""
    [[ -f "$_LSH_HACK_TUNNEL_PID_FILE" ]] && tunnel_pid=$(cat "$_LSH_HACK_TUNNEL_PID_FILE")

    # Block until explicitly exited, animating the same "tunnel active..."
    # spinner as `lsh tunnel`. `read` is a full-line read so Ctrl-C remains a
    # signal handled by _lsh_hack_expose_interrupt, while an empty line still
    # serves as the Enter-to-copy trigger.
    local dots=""
    while ! $stop && { [[ -z "$tunnel_pid" ]] || kill -0 "$tunnel_pid" 2>/dev/null; }; do
        printf '\rtunnel active%-3s' "$dots"
        dots="${dots}."
        [[ ${#dots} -gt 3 ]] && dots=""
        if $interactive; then
            local key=""
            if read -rs -t 0.3 key; then
                if [[ "$key" == q || "$key" == Q ]]; then
                    stop=true
                elif $can_copy; then
                    printf '%s' "$line" | wl-copy 2>/dev/null
                    printf ' (copied)'
                fi
            fi
        else
            sleep 0.3
        fi
    done
    printf '\r\033[K'
    _lsh_hack_expose_cleanup
}

lsh_hack_connect() {
    source "$SYSDIR/shared/cloudflare-tunnel.sh"

    local line="$1"
    if [[ -z "$line" ]]; then
        echo "Usage: lsh hack connect <user>@<host>@<tunnel-url>" >&2
        return 1
    fi

    if [[ ! "$line" =~ ^([^@]+)@([^@]+)@(https://[a-z0-9-]+\.trycloudflare\.com)/?$ ]]; then
        echo "lsh hack connect: unrecognized line, expected <user>@<host>@<tunnel-url>" >&2
        return 1
    fi

    local user="${BASH_REMATCH[1]}" host="${BASH_REMATCH[2]}" tunnel_url="${BASH_REMATCH[3]}"
    local tunnel_host="${tunnel_url#https://}"

    ensure_cloudflared || return 1

    local -a ssh_args=(
        -o "ProxyCommand=cloudflared access ssh --hostname ${tunnel_host}"
        "${user}@${host}"
    )

    # cloudflared's edge handshake sits in front of SSH's own, so the default
    # ten-second connect budget is too tight for a tunnelled connection.
    export LSH_CONNECT_TIMEOUT="${LSH_CONNECT_TIMEOUT:-30}"

    # Mosh is refused outright: a Quick Tunnel carries only the TCP SSH stream,
    # so Mosh's UDP client could never reach the remote server.
    if [[ ${LSH_INTERACTIVE_SHELL:-} == 1 && -t 0 && -t 1 && -z ${TMUX:-} ]] \
        && command -v tmux >/dev/null 2>&1; then
        lsh_stage_connection "$LSH_SELF" "$_RAW_SSH" 0 "${ssh_args[@]}"
        return $?
    fi

    lsh_exec_ssh "$_RAW_SSH" "${ssh_args[@]}"
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
