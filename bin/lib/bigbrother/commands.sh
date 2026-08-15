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

bigbrother_open_editor() {
    local path="$1" editor_value
    local -a editor_command=()

    editor_value="${VISUAL:-${EDITOR:-vi}}"
    read -r -a editor_command <<< "$editor_value"
    ((${#editor_command[@]} > 0)) || editor_command=(vi)
    "${editor_command[@]}" "$path"
}

bigbrother_header_line() {
    printf '# bb-name: %s\n' "$1"
}

bigbrother_recover_draft() {
    local temp="$1" mode="$2" name="$3"
    bigbrother_stash_draft "$temp" "$mode" "$name"
    rm -f -- "$temp"
    echo "bigbrother: draft kept; run 'bigbrother $mode $name' to fix it and continue" >&2
}

# Opens $EDITOR on a header + unit body, validates the declared name and the
# unit syntax, and reports the result via BB_RESULT_NAME/BB_RESULT_BODY.
# `mode` is "add" or "edit" — it namespaces drafts and appears in the resume
# hint, nothing else.
bigbrother_edit_buffer() {
    local mode="$1" name="$2" body="$3"
    local temp draft

    temp=$(mktemp --suffix=.service "$BIGBROTHER_RUNTIME_DIR/${mode}.XXXXXX") || return 1
    draft=$(bigbrother_draft_path "$mode" "$name")

    if [[ -f "$draft" ]]; then
        cp -- "$draft" "$temp"
        echo "bigbrother: resuming draft for '$name' from a previous failed attempt" >&2
    else
        { bigbrother_header_line "$name"; printf '%s\n' "$body"; } > "$temp"
    fi

    if ! bigbrother_open_editor "$temp"; then
        rm -f -- "$temp"
        echo "bigbrother: editor exited with an error" >&2
        return 1
    fi

    local header
    header=$(head -n1 "$temp")
    if [[ "$header" != "# bb-name: "* ]]; then
        echo "bigbrother: first line must stay '# bb-name: <name>'" >&2
        bigbrother_recover_draft "$temp" "$mode" "$name"
        return 1
    fi

    local declared_name
    declared_name=$(bigbrother_trim "${header#\# bb-name: }")
    if ! bigbrother_validate_name "$declared_name"; then
        bigbrother_recover_draft "$temp" "$mode" "$name"
        return 1
    fi

    local body_only
    body_only=$(tail -n +2 "$temp")
    printf '%s\n' "$body_only" > "$temp"

    if ! bigbrother_verify_unit "$temp"; then
        bigbrother_recover_draft "$temp" "$mode" "$name"
        return 1
    fi

    BB_RESULT_NAME="$declared_name"
    BB_RESULT_BODY="$body_only"
    rm -f -- "$temp"
    bigbrother_discard_draft "$mode" "$name"
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
    for n in "${transient_names[@]}"; do printf '~ %s (transient)\n' "$n"; done
    for n in "${enabled_names[@]}"; do printf '+ %s\n' "$n"; done
    for n in "${disabled_names[@]}"; do printf '%s- %s%s\n' "$dim" "$n" "$reset"; done
}

# Promotes an already-running transient unit to a persisted one. The
# transient unit shadows any on-disk file of the same name, so it must be
# stopped before the persistent unit can be enabled.
bigbrother_promote_transient() {
    local name="$1" exec_start workdir
    exec_start=$(bigbrother_exec_start_command "$name") || {
        echo "bigbrother: could not read command from transient unit '$name'" >&2
        return 1
    }
    workdir=$(bigbrother_working_directory "$name")
    bigbrother_stop "$name" 2>/dev/null || true
    bigbrother_write_unit "$name" "$exec_start" "$workdir" || return 1
    bigbrother_daemon_reload
}

bigbrother_cmd_add() {
    local input="${1:-}"
    [[ -z "$input" ]] && { echo "Usage: bigbrother add <path|transient-name>" >&2; return 1; }

    bigbrother_ensure_linger

    local suggested body promote_from=""

    if bigbrother_is_transient "$input" 2>/dev/null; then
        suggested="$input"
        promote_from="$input"
        local exec_start workdir
        exec_start=$(bigbrother_exec_start_command "$input") || {
            echo "bigbrother: could not read command from transient unit '$input'" >&2
            return 1
        }
        workdir=$(bigbrother_working_directory "$input")
        body=$(bigbrother_render_unit "$suggested" "$exec_start" "$workdir")
    else
        local abs
        abs=$(bigbrother_resolve_abs "$input") || {
            echo "bigbrother: no such path '$input'" >&2
            return 1
        }
        [[ -x "$abs" ]] || { echo "bigbrother: '$abs' is not executable" >&2; return 1; }
        suggested=$(bigbrother_name_from_path "$abs")
        body=$(bigbrother_render_unit "$suggested" "$abs" "$(dirname "$abs")")
    fi

    bigbrother_edit_buffer add "$suggested" "$body" || return 1
    local name="$BB_RESULT_NAME"

    if bigbrother_is_defined "$name"; then
        echo "bigbrother: '$name' already exists" >&2
        return 1
    fi

    [[ -n "$promote_from" ]] && { bigbrother_stop "$promote_from" 2>/dev/null || true; }

    bigbrother_write_unit_body "$name" "$BB_RESULT_BODY" || return 1
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
    bigbrother_ensure_linger

    if ! bigbrother_is_defined "$name"; then
        bigbrother_is_transient "$name" 2>/dev/null || {
            echo "bigbrother: '$name' is not defined" >&2
            return 1
        }
        bigbrother_promote_transient "$name" || return 1
        echo "bigbrother: promoted '$name' to a persisted service"
    fi

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
        echo "bigbrother: '$name' is running"
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
    local name="" follow=false raw=false arg
    for arg in "$@"; do
        case "$arg" in
            -f|--follow) follow=true ;;
            --raw)       raw=true ;;
            -*)          echo "bigbrother: unknown flag '$arg'" >&2; return 1 ;;
            *)
                if [[ -n "$name" ]]; then
                    echo "bigbrother: unexpected argument '$arg'" >&2
                    return 1
                fi
                name="$arg"
                ;;
        esac
    done

    [[ -z "$name" ]] && { echo "Usage: bigbrother logs <name> [-f] [--raw]" >&2; return 1; }
    bigbrother_logs "$name" "$follow" "$raw"
}

# `watch` is `logs -f` — the live view you get from a foregrounded process.
bigbrother_cmd_watch() {
    (($# > 0)) || { echo "Usage: bigbrother watch <name> [--raw]" >&2; return 1; }
    bigbrother_cmd_logs "$@" -f
}

bigbrother_cmd_edit() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother edit <name>" >&2; return 1; }
    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }

    local body
    body=$(cat -- "$(bigbrother_unit_path "$name")")

    bigbrother_edit_buffer edit "$name" "$body" || return 1
    local new_name="$BB_RESULT_NAME"

    if [[ "$new_name" != "$name" ]] && bigbrother_is_defined "$new_name"; then
        echo "bigbrother: '$new_name' already exists" >&2
        return 1
    fi

    bigbrother_write_unit_body "$name" "$BB_RESULT_BODY" || return 1

    if [[ "$new_name" != "$name" ]]; then
        bigbrother_rename_unit "$name" "$new_name" || return 1
        echo "bigbrother: updated and renamed '$name' to '$new_name'"
    else
        bigbrother_daemon_reload
        echo "bigbrother: updated '$name'"
    fi
}

bigbrother_cmd_mv() {
    local old="${1:-}" new="${2:-}"
    [[ -n "$old" && -n "$new" ]] || { echo "Usage: bigbrother mv <old> <new>" >&2; return 1; }
    bigbrother_is_defined "$old" || { echo "bigbrother: '$old' is not defined" >&2; return 1; }
    bigbrother_validate_name "$new" || return 1
    [[ "$old" == "$new" ]] && { echo "bigbrother: '$old' and '$new' are the same" >&2; return 1; }

    bigbrother_rename_unit "$old" "$new" || return 1
    echo "bigbrother: renamed '$old' to '$new'"
}

bigbrother_cmd_help() {
    cat <<'EOF'
Usage: bigbrother [command]
       bb [command]

Bare shortcuts:
    bb ./binary            Run a binary now (transient, gone on reboot)
    bb <name>              Watch a running service's live output

Commands:
    ls, list                List all services (enabled plain, disabled dim, transient marked)
    add, a <path|name>       Opens $EDITOR on a unit draft, then defines + enables + starts it
    rm, remove <name>        Stop, disable, and delete a service definition
    mv, rename <old> <new>   Rename a defined service, preserving its enabled/active state
    enable, up <name>        Enable + start (persists across reboot)
    disable, down <name>     Disable + stop (definition kept)
    run <path|name>          Run now — transient if a path, start if a defined name
    stop <name>               Stop now (stays defined)
    restart <name>
    watch, tail, attach <name>  Live view of the process output (same as `bb <name>`)
    logs <name> [-f] [--raw]  Past output; -f follows, --raw adds journald timestamps
    edit, e <name>             Opens $EDITOR on the unit; a changed 'bb-name' header renames it
    help, -h, --help

All operations are systemd --user (no sudo).
EOF
}
