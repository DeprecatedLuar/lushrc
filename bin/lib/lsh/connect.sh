#!/usr/bin/env bash
# Smart interactive connections for lsh.
#
# The entrypoint decides whether a call is eligible. This module owns the
# terminal adapters: tmux stages a connection until it becomes interactive,
# while the transport adapter prefers Mosh and falls back to SSH before Mosh
# has established its UDP client.

_LSH_CONNECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lsh_is_plain_connection() {
    [[ $# -eq 1 && "$1" != -* ]]
}

# Accept targets that resolve normally, plus SSH config aliases whose HostName
# rewrites the name. This is intentionally a preflight only: it does not open a
# connection or require the SSH port to be reachable.
lsh_target_is_valid() {
    local raw_ssh=$1
    local target=$2
    local requested_host effective_host config

    requested_host=${target##*@}
    requested_host=${requested_host#[}
    requested_host=${requested_host%]}

    config=$("$raw_ssh" -G -- "$target" 2>/dev/null) || return 1
    effective_host=$(awk 'tolower($1) == "hostname" { print $2; exit }' <<< "$config")
    [[ -n $effective_host ]] || return 1

    # A different effective HostName means SSH matched a configured alias.
    [[ ${effective_host,,} != ${requested_host,,} ]] && return 0

    command -v getent >/dev/null 2>&1 || return 0
    getent ahosts "$effective_host" >/dev/null 2>&1
}

lsh_has_compatible_term() {
    case "${TERM:-}" in
        xterm-kitty|alacritty|alacritty-direct|foot|foot-extra|wezterm) return 0 ;;
        *) return 1 ;;
    esac
}

lsh_exec_ssh() {
    local raw_ssh=$1
    shift

    if lsh_has_compatible_term; then
        TERM=xterm-256color exec "$raw_ssh" "$@"
    fi
    exec "$raw_ssh" "$@"
}

lsh_set_staged_transport_label() {
    local transport=$1
    [[ -n ${TMUX_PANE:-} ]] || return 0
    tmux set-option -w -t "$TMUX_PANE" @lsh_transport "$transport" 2>/dev/null || true
}

lsh_prepare_mosh() {
    local raw_ssh=$1
    shift

    LSH_MOSH_SSH="$raw_ssh"
    LSH_MOSH_TARGET=""

    case $# in
        1)
            LSH_MOSH_TARGET=$1
            ;;
        3)
            [[ $1 == -p && $2 =~ ^[0-9]+$ ]] || return 1
            printf -v LSH_MOSH_SSH '%q -p %q' "$raw_ssh" "$2"
            LSH_MOSH_TARGET=$3
            ;;
        *)
            return 1
            ;;
    esac
}

lsh_mosh_client_started() {
    [[ -n ${LSH_TMUX_SESSION:-} ]] || return 1
    [[ $(tmux show-options -v -t "$LSH_TMUX_SESSION" @lsh_mosh_started 2>/dev/null) == 1 ]]
}

lsh_run_staged_transport() {
    local raw_ssh=$1
    local allow_mosh=$2
    shift 2
    local client status

    client=$(command -v mosh-client 2>/dev/null || true)
    if [[ $allow_mosh == 1 && -n $client ]] \
        && command -v mosh >/dev/null 2>&1 \
        && lsh_prepare_mosh "$raw_ssh" "$@"; then
        lsh_set_staged_transport_label mosh
        if lsh_has_compatible_term; then
            TERM=xterm-256color LSH_MOSH_CLIENT="$client" \
                mosh --client="$_LSH_CONNECT_DIR/mosh-client" \
                --ssh="$LSH_MOSH_SSH" -- "$LSH_MOSH_TARGET"
        else
            LSH_MOSH_CLIENT="$client" \
                mosh --client="$_LSH_CONNECT_DIR/mosh-client" \
                --ssh="$LSH_MOSH_SSH" -- "$LSH_MOSH_TARGET"
        fi
        status=$?

        # Once the UDP client has started, returning to SSH later would create
        # a surprising new session. Signals also represent an explicit stop.
        if lsh_mosh_client_started || (( status >= 128 )); then
            return "$status"
        fi

        # Remove bootstrap diagnostics before the SSH attempt. If the user is
        # already attached at an authentication prompt, this also gives the
        # fallback a clean terminal.
        if [[ -n ${TMUX_PANE:-} ]]; then
            tmux clear-history -t "$TMUX_PANE" 2>/dev/null || true
            printf '\033[H\033[2J'
        fi
    fi

    lsh_set_staged_transport_label ssh
    lsh_exec_ssh "$raw_ssh" "$@"
}

lsh_remote_has_mosh() {
    local raw_ssh=$1
    shift
    "$raw_ssh" "$@" 'command -v mosh-server >/dev/null 2>&1'
}

lsh_run_direct_smart_connection() {
    local raw_ssh=$1
    local allow_mosh=$2
    shift 2
    local status

    if [[ $allow_mosh == 1 ]] \
        && command -v mosh >/dev/null 2>&1 \
        && lsh_prepare_mosh "$raw_ssh" "$@"; then
        lsh_remote_has_mosh "$raw_ssh" "$@"
        status=$?
        case $status in
            0)
                if lsh_has_compatible_term; then
                    TERM=xterm-256color exec mosh --ssh="$LSH_MOSH_SSH" -- "$LSH_MOSH_TARGET"
                fi
                exec mosh --ssh="$LSH_MOSH_SSH" -- "$LSH_MOSH_TARGET"
                ;;
            255)
                return "$status"
                ;;
        esac
    fi

    lsh_exec_ssh "$raw_ssh" "$@"
}

lsh_tmux_pane_output() {
    local pane=$1
    tmux capture-pane -p -t "$pane" -S - 2>/dev/null \
        | sed -e '/^Pane is dead (status .*).*$/d' -e '/^[[:space:]]*$/d'
}

lsh_tmux_transport_started() {
    local session=$1
    [[ $(tmux show-options -v -t "$session" @lsh_transport_started 2>/dev/null) == 1 ]]
}

lsh_output_needs_interaction() {
    local output=${1,,}
    [[ $output == *'password:'* \
        || $output == *'password for '* \
        || $output == *'enter passphrase'* \
        || $output == *'yes/no/'* \
        || $output == *'verification code'* \
        || $output == *'security key'* \
        || $output == *'pin:'* ]]
}

lsh_output_is_connection_failure() {
    local output=${1,,}
    [[ $output == *'connection refused'* \
        || $output == *'could not resolve hostname'* \
        || $output == *'name or service not known'* \
        || $output == *'no route to host'* \
        || $output == *'network is unreachable'* \
        || $output == *'connection timed out'* \
        || $output == *'operation timed out'* \
        || $output == *'connection reset'* \
        || $output == *'connection closed by'* \
        || $output == *'permission denied'* \
        || $output == *'host key verification failed'* \
        || $output == *'remote host identification has changed'* \
        || $output == *'kex_exchange_identification'* \
        || $output == *'no matching host key type'* \
        || $output == *'no matching key exchange'* \
        || $output == *'bad configuration option'* \
        || $output == *'did not find remote ip address'* \
        || $output == *'did not find mosh server startup message'* ]]
}

lsh_tmux_session_base() {
    local target=$1
    local base

    base=${target##*@}
    base=${base#[}
    base=${base%]}
    base=${base//[^[:alnum:]_-]/-}
    while [[ $base == -* ]]; do base=${base#-}; done
    while [[ $base == *- ]]; do base=${base%-}; done
    printf 'lsh-%s\n' "${base:-remote}"
}

lsh_tmux_connection_info() {
    local raw_ssh=$1
    local target=$2
    local user host effective_host config

    host=${target##*@}
    host=${host#[}
    host=${host%]}
    config=$("$raw_ssh" -G -- "$target" 2>/dev/null || true)

    if [[ $target == *@* ]]; then
        user=${target%@*}
    else
        user=$(awk 'tolower($1) == "user" { print $2; exit }' <<< "$config")
    fi
    effective_host=$(awk 'tolower($1) == "hostname" { print $2; exit }' <<< "$config")

    LSH_TMUX_LABEL_RESULT=${user:+$user@}$host
    LSH_TMUX_HOST_RESULT=${effective_host:-$host}
}

lsh_tmux_session_exists() {
    tmux has-session -t "=$1" 2>/dev/null
}

lsh_stage_connection() {
    local self=$1
    local raw_ssh=$2
    local allow_mosh=$3
    shift 3

    local connection_target=${!#}
    local base label ping_host session target status_format latency_format
    local suffix=1
    local command output dead status
    local poll_interval="${LSH_STAGE_POLL_INTERVAL:-0.05}"

    base=$(lsh_tmux_session_base "$connection_target")
    lsh_tmux_connection_info "$raw_ssh" "$connection_target"
    label=$LSH_TMUX_LABEL_RESULT
    ping_host=$LSH_TMUX_HOST_RESULT
    session="$base-0"
    while lsh_tmux_session_exists "$session"; do
        session="$base-$suffix"
        ((suffix++))
    done
    target="$session:0.0"

    while ! tmux new-session -d -s "$session" -c "$PWD" 'sleep 2147483647'; do
        lsh_tmux_session_exists "$session" || return 1
        session="$base-$suffix"
        ((suffix++))
        target="$session:0.0"
    done

    status_format='#{@lsh_transport} · #{@lsh_label}'
    printf -v latency_format '#(%q #{window_id})' "$_LSH_CONNECT_DIR/latency"

    printf -v command \
        'export LSH_STAGE_CHILD=1 LSH_STAGE_MOSH=%q LSH_RAW_SSH=%q LSH_TMUX_SESSION=%q; %q' \
        "$allow_mosh" "$raw_ssh" "$session" "$self"
    local arg
    for arg in "$@"; do
        printf -v command '%s %q' "$command" "$arg"
    done
    printf -v command \
        '%s; status=$?; tmux set-option -t %q @lsh_exit_status "$status" 2>/dev/null; exit "$status"' \
        "$command" "$session"

    if ! tmux rename-window -t "$target" "$label" \
        \; set-option -w -t "$target" automatic-rename off \
        \; set-option -w -t "$target" @lsh_transport connecting \
        \; set-option -w -t "$target" @lsh_label "$label" \
        \; set-option -w -t "$target" @lsh_host "$ping_host" \
        \; set-option -w -t "$target" window-status-format "$status_format" \
        \; set-option -w -t "$target" window-status-current-format "$status_format" \
        \; set-option -t "$session" @lsh_managed 1 \
        \; set-option -t "$session" @lsh_target "$connection_target" \
        \; set-option -t "$session" status-right "$latency_format" \
        \; set-option -t "$session" status-right-length 12 \
        \; set-option -t "$session" status-interval 5 \
        \; set-option -t "$session" remain-on-exit on \
        \; respawn-pane -k -t "$target" "$command"; then
        tmux kill-session -t "=$session" 2>/dev/null || true
        return 1
    fi

    trap 'tmux kill-session -t "$session" 2>/dev/null || true; exit 130' INT TERM HUP

    while tmux has-session -t "$session" 2>/dev/null; do
        dead=$(tmux display-message -p -t "$target" '#{pane_dead}' 2>/dev/null)
        if [[ $dead == 1 ]]; then
            status=$(tmux show-options -v -t "$session" @lsh_exit_status 2>/dev/null)
            output=$(lsh_tmux_pane_output "$target")
            tmux kill-session -t "$session" 2>/dev/null || true
            trap - INT TERM HUP
            [[ -n $output ]] && printf '%s\n' "$output" >&2
            [[ $status =~ ^[0-9]+$ ]] || status=1
            return "$status"
        fi

        output=$(lsh_tmux_pane_output "$target")
        if lsh_tmux_transport_started "$session" \
            || lsh_output_needs_interaction "$output" \
            || { [[ -n $output ]] && ! lsh_output_is_connection_failure "$output"; }; then
            dead=$(tmux display-message -p -t "$target" '#{pane_dead}' 2>/dev/null)
            [[ $dead == 1 ]] && continue

            tmux set-option -t "$session" remain-on-exit off
            trap - INT TERM HUP
            tmux attach-session -t "$session"
            return $?
        fi

        sleep "$poll_interval"
    done

    trap - INT TERM HUP
    return 1
}
