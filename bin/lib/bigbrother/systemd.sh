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
    systemd-run --user --unit="$name" --description="$name" \
        --property="Restart=always" --property="RestartSec=5" \
        --working-directory="$workdir" \
        -- "$@"
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
    systemctl --user enable --now "$1.service"
}

bigbrother_disable_now() {
    systemctl --user disable --now "$1.service"
}

bigbrother_logs() {
    local name="$1" follow="${2:-false}"
    if $follow; then
        journalctl --user -u "$name.service" -f
    else
        journalctl --user -u "$name.service"
    fi
}

bigbrother_edit() {
    systemctl --user edit --full "$1.service"
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
