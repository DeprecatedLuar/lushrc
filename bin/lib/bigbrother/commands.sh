#!/usr/bin/env bash

# One function per verb.

bigbrother_resolve_abs() {
    local path="$1"
    [[ -e "$path" ]] || return 1
    (cd "$(dirname "$path")" && printf '%s/%s\n' "$PWD" "$(basename "$path")")
}

bigbrother_name_from_path() {
    basename "$1"
}

bigbrother_cmd_ls() {
    local name found=false dim="" reset=""
    local -a enabled_names=() disabled_names=() transient_names=()

    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        dim=$'\033[2m'
        reset=$'\033[0m'
    fi

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        found=true
        if bigbrother_is_enabled "$name"; then
            enabled_names+=("$name")
        else
            disabled_names+=("$name")
        fi
    done < <(bigbrother_defined_names)

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        found=true
        transient_names+=("$name")
    done < <(bigbrother_transient_names)

    $found || { echo "No services."; return 0; }

    local n
    for n in "${enabled_names[@]}"; do printf '%s\n' "$n"; done
    for n in "${disabled_names[@]}"; do printf '%s%s%s\n' "$dim" "$n" "$reset"; done
    for n in "${transient_names[@]}"; do printf '%s (transient)\n' "$n"; done
}

bigbrother_cmd_add() {
    local input="${1:-}"
    [[ -z "$input" ]] && { echo "Usage: bigbrother add <path|transient-name>" >&2; return 1; }

    bigbrother_ensure_linger

    local name exec_start workdir

    if bigbrother_is_transient "$input" 2>/dev/null; then
        # Promote an already-running transient unit. The transient unit shadows
        # any on-disk file of the same name, so it must be stopped before the
        # persistent unit can be enabled.
        name="$input"
        exec_start=$(bigbrother_exec_start_command "$name") || {
            echo "bigbrother: could not read command from transient unit '$name'" >&2
            return 1
        }
        workdir=$(bigbrother_working_directory "$name")
        bigbrother_stop "$name" 2>/dev/null || true
    else
        local abs
        abs=$(bigbrother_resolve_abs "$input") || {
            echo "bigbrother: no such path '$input'" >&2
            return 1
        }
        [[ -x "$abs" ]] || { echo "bigbrother: '$abs' is not executable" >&2; return 1; }
        name=$(bigbrother_name_from_path "$abs")
        exec_start="$abs"
        workdir=$(dirname "$abs")
    fi

    bigbrother_write_unit "$name" "$exec_start" "$workdir" || return 1
    bigbrother_daemon_reload
    bigbrother_enable_now "$name"
    echo "bigbrother: added and started '$name'"
}

bigbrother_cmd_rm() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother rm <name>" >&2; return 1; }
    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }

    bigbrother_disable_now "$name" 2>/dev/null
    bigbrother_delete_unit "$name"
    bigbrother_daemon_reload
    echo "bigbrother: removed '$name'"
}

bigbrother_cmd_enable() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother enable <name>" >&2; return 1; }
    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }
    bigbrother_ensure_linger
    bigbrother_enable_now "$name"
    echo "bigbrother: enabled '$name'"
}

bigbrother_cmd_disable() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother disable <name>" >&2; return 1; }
    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }
    bigbrother_disable_now "$name"
    echo "bigbrother: disabled '$name'"
}

bigbrother_cmd_run() {
    local input="${1:-}"
    [[ -z "$input" ]] && { echo "Usage: bigbrother run <path|name>" >&2; return 1; }

    bigbrother_ensure_linger

    if [[ "$input" == */* ]] || [[ -f "$input" && -x "$input" ]]; then
        local abs name
        abs=$(bigbrother_resolve_abs "$input") || {
            echo "bigbrother: no such path '$input'" >&2
            return 1
        }
        [[ -x "$abs" ]] || { echo "bigbrother: '$abs' is not executable" >&2; return 1; }
        name=$(bigbrother_name_from_path "$abs")

        if bigbrother_is_defined "$name"; then
            echo "bigbrother: '$name' is already a defined service; use 'bigbrother run $name'" >&2
            return 1
        fi
        if bigbrother_is_transient "$name" 2>/dev/null && bigbrother_is_running "$name"; then
            echo "bigbrother: '$name' is already running" >&2
            return 1
        fi

        bigbrother_run_transient "$name" "$(dirname "$abs")" "$abs"
        echo "bigbrother: running '$name' (transient, not persisted)"
        return
    fi

    # bare name: must be a defined service
    bigbrother_is_defined "$input" || {
        echo "bigbrother: '$input' is not a defined service and not a path" >&2
        return 1
    }
    bigbrother_start "$input"
    echo "bigbrother: started '$input'"
}

bigbrother_cmd_stop() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother stop <name>" >&2; return 1; }
    bigbrother_stop "$name"
    echo "bigbrother: stopped '$name'"
}

bigbrother_cmd_restart() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother restart <name>" >&2; return 1; }
    bigbrother_restart "$name"
    echo "bigbrother: restarted '$name'"
}

bigbrother_cmd_logs() {
    local name="${1:-}" follow=false
    [[ "${2:-}" == "-f" ]] && follow=true
    [[ -z "$name" ]] && { echo "Usage: bigbrother logs <name> [-f]" >&2; return 1; }
    bigbrother_logs "$name" "$follow"
}

bigbrother_cmd_edit() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother edit <name>" >&2; return 1; }
    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }
    bigbrother_edit "$name"
    bigbrother_daemon_reload
}

bigbrother_cmd_help() {
    cat <<'EOF'
Usage: bigbrother [command]
       bb [command]

Bare path shortcut:
    bb ./binary            Run a binary now (transient, gone on reboot)

Commands:
    ls, list                List all services (enabled plain, disabled dim, transient marked)
    add <path|name>          Define + enable + start a service (or promote a running transient one)
    rm, remove <name>        Stop, disable, and delete a service definition
    enable, up <name>        Enable + start (persists across reboot)
    disable, down <name>     Disable + stop (definition kept)
    run <path|name>          Run now — transient if a path, start if a defined name
    stop <name>               Stop now (stays defined)
    restart <name>
    logs <name> [-f]          Show/follow logs via journalctl
    edit <name>                Edit the raw unit file, then daemon-reload
    help, -h, --help

All operations are systemd --user (no sudo).
EOF
}
