#!/usr/bin/env bash

# All systemctl/systemd-run/loginctl calls live here.

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

# Polls a just-launched unit's ActiveState for a short grace window so `run`
# can report whether it actually survived instead of blindly saying
# "running". Prints a verdict (and a log tail on failure) and returns
# non-zero if it failed or exited with an error.
bigbrother_verify_launch() {
    local name="$1" attempts=20 sleep_for=0.1
    local state result i

    for ((i = 0; i < attempts; i++)); do
        state=$(systemctl --user show -p ActiveState --value "$name.service" 2>/dev/null)
        case "$state" in
            active|activating|reloading)
                sleep "$sleep_for"
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
                    echo "bigbrother: '$name' ran and exited successfully"
                    return 0
                fi
                echo "bigbrother: '$name' exited with an error (${result:-unknown})" >&2
                journalctl --user -u "$name.service" -n 20 --no-pager 2>/dev/null
                return 1
                ;;
            *)
                sleep "$sleep_for"
                ;;
        esac
    done

    echo "bigbrother: '$name' is running"
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
