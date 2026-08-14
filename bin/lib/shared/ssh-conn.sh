#!/usr/bin/env bash
# ssh-conn.sh — parse a connection spec into a reusable SSH/rsync connection
#
# parse_conn <[user@]host[:port]> [flag_user] [flag_port]
#   Outputs (globals):
#     CONN_HOST     host, with .N shorthand expanded to a full LAN IP
#     CONN_PORT     port, or empty
#     CONN_USER     user, or empty
#     CONN_TARGET   [user@]host — the argument ssh and rsync take
#
# Once parsed, run things over that connection:
#     conn_ssh <command...>       execute a command on the remote
#     conn_ssh_pipe <command...>  same, but the local stdin is fed to the remote
#     conn_rsync <args...>        rsync using the parsed port
#
# Requires: shared/net.sh (expand_local_ip)

CONN_HOST=""
CONN_PORT=""
CONN_USER=""
CONN_TARGET=""
CONN_SSH_ARGS=()

parse_conn() {
    local spec="$1" flag_user="${2:-}" flag_port="${3:-}"

    CONN_USER="$flag_user"
    CONN_PORT=""

    if [[ "$spec" == *@* ]]; then
        CONN_USER="${spec%%@*}"
        spec="${spec#*@}"
    fi

    if [[ "$spec" == *:* ]]; then
        local colon_port="${spec##*:}"
        if [[ -n "$flag_port" && "$flag_port" != "$colon_port" ]]; then
            echo "error: conflicting ports (-p $flag_port vs :$colon_port)" >&2
            return 1
        fi
        CONN_PORT="$colon_port"
        spec="${spec%:*}"
    else
        CONN_PORT="$flag_port"
    fi

    CONN_HOST=$(expand_local_ip "$spec") || return 1

    [[ -n "$CONN_USER" ]] && CONN_TARGET="$CONN_USER@$CONN_HOST" || CONN_TARGET="$CONN_HOST"

    CONN_SSH_ARGS=()
    [[ -n "$CONN_PORT" ]] && CONN_SSH_ARGS+=("-p" "$CONN_PORT")

    return 0
}

# -n keeps ssh from swallowing our stdin — otherwise a remote probe run before
# an interactive prompt eats the answer the user is about to give.
conn_ssh() {
    ssh -n "${CONN_SSH_ARGS[@]}" "$CONN_TARGET" "$@"
}

conn_ssh_pipe() {
    ssh "${CONN_SSH_ARGS[@]}" "$CONN_TARGET" "$@"
}

conn_rsync() {
    local rsh_args=()
    [[ -n "$CONN_PORT" ]] && rsh_args+=("--rsh" "ssh -p $CONN_PORT")
    rsync "${rsh_args[@]}" "$@"
}
