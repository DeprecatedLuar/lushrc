#!/usr/bin/env bash

# All systemctl/systemd-run/loginctl calls live here.

# Unit state is reported asynchronously, so both "did it survive startup?" and
# "is it really down?" are polls rather than single reads.
BIGBROTHER_POLL_INTERVAL=0.1
BIGBROTHER_LAUNCH_POLL_ATTEMPTS=20
BIGBROTHER_STOP_POLL_ATTEMPTS=30

bigbrother_ensure_linger() {
    local state
    state=$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)
    [[ "$state" == "yes" ]] && return 0

    if loginctl enable-linger "$USER" 2>/dev/null; then
        echo "bigbrother: enabled linger for $USER (services now survive logout)"
        return 0
    fi

    echo "bigbrother: could not enable linger automatically." >&2
    echo "bigbrother: run this manually so services survive logout: loginctl enable-linger $USER" >&2
}

bigbrother_daemon_reload() {
    systemctl --user daemon-reload
}

bigbrother_is_defined() {
    [[ -f "$(bigbrother_unit_path "$1")" ]]
}

bigbrother_is_enabled() {
    systemctl --user is-enabled "$1.service" &>/dev/null
}

bigbrother_is_transient() {
    [[ "$(systemctl --user show -p Transient --value "$1.service" 2>/dev/null)" == "yes" ]]
}

bigbrother_is_running() {
    systemctl --user is-active "$1.service" &>/dev/null
}

bigbrother_defined_names() {
    local svc
    for svc in "$BIGBROTHER_UNIT_DIR"/*.service; do
        [[ -f "$svc" ]] || continue
        basename "$svc" .service
    done
}

bigbrother_transient_names() {
    systemctl --user list-units --type=service --state=running --no-legend --plain 2>/dev/null |
        awk '{print $1}' | while IFS= read -r unit; do
            local name="${unit%.service}"
            bigbrother_is_transient "$name" && printf '%s\n' "$name"
        done
}

bigbrother_running_names() {
    local scope="$1" flag
    [[ "$scope" == user ]] && flag=--user || flag=--system
    systemctl "$flag" list-units --type=service --state=running --no-legend --plain 2>/dev/null |
        awk '{print $1}' | while IFS= read -r unit; do
            printf '%s\n' "${unit%.service}"
        done
}

bigbrother_run_transient() {
    local name="$1" workdir="$2"
    shift 2

    local -a env_args=() kv
    for kv in "${BIGBROTHER_SERVICE_ENV[@]}"; do
        env_args+=(--setenv="$kv")
    done

    # No Restart= here on purpose: `run` is ephemeral, one-shot — if it
    # dies, it dies. Persistence (Restart=always) only comes from `add`
    # or `enable`, which write a real unit file via BIGBROTHER_UNIT_TEMPLATE.
    systemd-run --user --quiet --unit="$name" --description="$name" \
        --working-directory="$workdir" \
        "${env_args[@]}" \
        -- "$@"
}

# Polls a just-launched unit's ActiveState for a short grace window so callers
# can tell whether it actually survived instead of blindly reporting success.
# Stays silent when the unit is still up — the caller owns that status line, so
# that a success can never be confused with a name-collision error the way
# "'x' is running" and "'x' is already running" once were. Prints a log tail
# and returns non-zero if it failed or exited with an error. On success reports
# which kind of success it was in BB_LAUNCH_STATE (running|exited), since a
# long-lived service and a one-shot that finished need different confirmations.
bigbrother_verify_launch() {
    local name="$1"
    local state result i

    BB_LAUNCH_STATE=""

    for ((i = 0; i < BIGBROTHER_LAUNCH_POLL_ATTEMPTS; i++)); do
        state=$(systemctl --user show -p ActiveState --value "$name.service" 2>/dev/null)
        case "$state" in
            active|activating|reloading)
                sleep "$BIGBROTHER_POLL_INTERVAL"
                continue
                ;;
            failed)
                echo "bigbrother: '$name' failed to start" >&2
                journalctl --user -u "$name.service" -n 20 --no-pager 2>/dev/null
                return 1
                ;;
            inactive|deactivating)
                result=$(systemctl --user show -p Result --value "$name.service" 2>/dev/null)
                if [[ "$result" == success ]]; then
                    BB_LAUNCH_STATE=exited
                    echo "bigbrother: '$name' ran and exited successfully"
                    return 0
                fi
                echo "bigbrother: '$name' exited with an error (${result:-unknown})" >&2
                journalctl --user -u "$name.service" -n 20 --no-pager 2>/dev/null
                return 1
                ;;
            *)
                sleep "$BIGBROTHER_POLL_INTERVAL"
                ;;
        esac
    done

    BB_LAUNCH_STATE=running
}

# `systemctl stop` returns once its job completes, but a Restart=always unit can
# still be settling out of auto-restart. Confirms the unit is really down before
# a caller deletes the unit file out from under a live process.
bigbrother_wait_stopped() {
    local name="$1" state i

    for ((i = 0; i < BIGBROTHER_STOP_POLL_ATTEMPTS; i++)); do
        state=$(systemctl --user show -p ActiveState --value "$name.service" 2>/dev/null)
        case "$state" in
            inactive|failed|"") return 0 ;;
        esac
        sleep "$BIGBROTHER_POLL_INTERVAL"
    done
    return 1
}

# Clears a unit's failed state so it stops occupying `systemctl --user --failed`
# after bigbrother has finished with it. Never fatal: there may be nothing to
# clear, which is the normal case.
bigbrother_reset_failed() {
    systemctl --user reset-failed "$1.service" 2>/dev/null || true
}

bigbrother_start() {
    systemctl --user start "$1.service"
}

bigbrother_stop() {
    systemctl --user stop "$1.service"
}

bigbrother_restart() {
    systemctl --user restart "$1.service"
}

bigbrother_enable_now() {
    local output status=0
    output=$(systemctl --user enable --now "$1.service" 2>&1) || status=$?
    ((status == 0)) || { printf '%s\n' "$output" >&2; return $status; }
}

bigbrother_disable_now() {
    local output status=0
    output=$(systemctl --user disable --now "$1.service" 2>&1) || status=$?
    ((status == 0)) || { printf '%s\n' "$output" >&2; return $status; }
}

bigbrother_logs() {
    local name="$1" follow="${2:-false}" raw="${3:-false}"
    local -a args=(--user -u "$name.service")

    # `-o cat` prints the bare message, no timestamp/host/unit prefix — what the
    # process actually wrote, ANSI colors included.
    if ! $raw; then args+=(-o cat); fi
    if $follow; then args+=(-f); fi

    journalctl "${args[@]}"
}

# Extracts the command line from `systemctl show -p ExecStart --value`, whose
# format is `{ path=... ; argv[]=/abs/path arg1 arg2 ; ignore_errors=no ; ... }`.
bigbrother_exec_start_command() {
    local blob
    blob=$(systemctl --user show -p ExecStart --value "$1.service" 2>/dev/null)
    [[ "$blob" =~ argv\[\]=([^;]*)\; ]] || return 1
    local cmd="${BASH_REMATCH[1]}"
    # trim surrounding whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    cmd="${cmd%"${cmd##*[![:space:]]}"}"
    printf '%s\n' "$cmd"
}

bigbrother_working_directory() {
    systemctl --user show -p WorkingDirectory --value "$1.service" 2>/dev/null
}
