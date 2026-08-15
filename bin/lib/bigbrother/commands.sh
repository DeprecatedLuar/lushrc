#!/usr/bin/env bash

# One function per verb.

# `run` derives a service name from its command's binary and appends .1, .2, …
# when that name is taken, so an ad-hoc launch never has to refuse over a name
# collision. The cap only exists to keep a pathological loop bounded.
BIGBROTHER_NAME_MAX_SUFFIX=99

# A name is spoken for by an on-disk unit or by a loaded transient one. Both
# matter: a transient unit shadows any file of the same name.
bigbrother_name_taken() {
    bigbrother_is_defined "$1" || bigbrother_is_transient "$1" 2>/dev/null
}

# A service's default name is its command's basename — `agentctl run` → agentctl.
# Deliberately does not sanitize: a basename that doesn't fit
# BIGBROTHER_NAME_PATTERN is an error pointing at -n, not something to quietly
# mangle into a name the caller never asked for.
bigbrother_derive_name() {
    local base
    base=$(basename -- "$1")
    bigbrother_validate_name "$base" 2>/dev/null || {
        echo "bigbrother: cannot derive a service name from '$1'; pass -n <name>" >&2
        return 1
    }
    printf '%s\n' "$base"
}

bigbrother_free_name() {
    local base="$1" candidate="$1" i=0
    while bigbrother_name_taken "$candidate"; do
        if ((++i > BIGBROTHER_NAME_MAX_SUFFIX)); then
            echo "bigbrother: no free name for '$base' after $BIGBROTHER_NAME_MAX_SUFFIX attempts" >&2
            return 1
        fi
        candidate="$base.$i"
    done
    printf '%s\n' "$candidate"
}

# Shared -n/-c/--workdir parser for `add` and `run`, so the two verbs can't
# drift. They differ only in what a bare positional means: for `run` it opens
# the command line, for `add` it is the service name — whose command can only
# arrive via -c, which keeps `bb add <name>` unambiguously the editor path.
# Everything after -c is taken verbatim, so `bb run agentctl run` doesn't try
# to read that second `run` as a flag.
# Results land in BB_ARG_NAME / BB_ARG_WORKDIR / BB_ARG_COMMAND.
bigbrother_parse_launch_args() {
    local positional="$1" arg
    shift

    BB_ARG_NAME=""
    BB_ARG_WORKDIR=""
    BB_ARG_COMMAND=()

    while (($#)); do
        arg="$1"
        case "$arg" in
            -c|--command)
                shift
                (($# > 0)) || { echo "bigbrother: -c/--command requires a command" >&2; return 1; }
                BB_ARG_COMMAND=("$@")
                return 0
                ;;
            -n|--name)
                shift
                [[ -n "${1:-}" ]] || { echo "bigbrother: -n/--name requires a value" >&2; return 1; }
                BB_ARG_NAME="$1"
                ;;
            --name=*)    BB_ARG_NAME="${arg#--name=}" ;;
            --workdir)
                shift
                [[ -n "${1:-}" ]] || { echo "bigbrother: --workdir requires a value" >&2; return 1; }
                BB_ARG_WORKDIR="$1"
                ;;
            --workdir=*) BB_ARG_WORKDIR="${arg#--workdir=}" ;;
            -*)          echo "bigbrother: unknown flag '$arg'" >&2; return 1 ;;
            *)
                if [[ "$positional" == command ]]; then
                    BB_ARG_COMMAND=("$@")
                    return 0
                fi
                [[ -z "$BB_ARG_NAME" ]] || {
                    echo "bigbrother: unexpected argument '$arg'" >&2
                    return 1
                }
                BB_ARG_NAME="$arg"
                ;;
        esac
        shift
    done
}

# The one launch path. `add` and `run` both come through here, so a service is
# never persisted on the strength of a command that was never actually run.
bigbrother_launch_transient() {
    local name="$1" workdir="$2"
    shift 2

    bigbrother_run_transient "$name" "$workdir" "$@" || return 1
    bigbrother_verify_launch "$name" || {
        bigbrother_reset_failed "$name"
        return 1
    }
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
        if [[ "$(head -n1 "$temp")" != "# bb-name: "* ]]; then
            # The stashed draft lost its header line (e.g. the previous
            # editor session deleted it) — restore it so the editor always
            # opens with the header present instead of repeating the same
            # "first line must stay" failure every resume.
            { bigbrother_header_line "$name"; cat -- "$temp"; } > "${temp}.headered"
            mv -- "${temp}.headered" "$temp"
        fi
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

# Prints "+ name" (enabled/added), "~ name" (transient, live), a dim "- name"
# (disabled), or a strikethrough "x name" (removed) — mark is one of + ~ - x.
# Shared by `ls` and the add/run/enable/disable/rm command feedback so they all
# agree on what each marker means. Styling is TTY-only; the ASCII mark itself
# always stays so piped/logged output remains distinguishable and greppable.
bigbrother_status_line() {
    local mark="$1" name="$2" style="" reset=""

    # + and ~ both mean "this is up", so neither is dimmed.
    case "$mark" in
        +|'~') printf '%s %s\n' "$mark" "$name"; return ;;
    esac

    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        reset=$'\033[0m'
        [[ "$mark" == x ]] && style=$'\033[2m\033[9m' || style=$'\033[2m'
    fi
    printf '%s%s %s%s\n' "$style" "$mark" "$name" "$reset"
}

bigbrother_cmd_get() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother get <name>" >&2; return 1; }

    if bigbrother_is_transient "$name" 2>/dev/null; then
        local running="stopped"
        bigbrother_is_running "$name" && running="running"
        printf "name     %s\n" "$name"
        printf "type     transient\n"
        printf "status   %s\n" "$running"
        printf "command  %s\n" "$(bigbrother_exec_start_command "$name" 2>/dev/null)"
        printf "workdir  %s\n" "$(bigbrother_working_directory "$name" 2>/dev/null)"
        return 0
    fi

    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }

    local enabled="disabled" running="stopped"
    bigbrother_is_enabled "$name" && enabled="enabled"
    bigbrother_is_running "$name" && running="running"

    printf "name     %s\n" "$name"
    printf "status   %s / %s\n" "$enabled" "$running"
    printf "command  %s\n" "$(bigbrother_exec_start_command "$name" 2>/dev/null)"
    printf "workdir  %s\n" "$(bigbrother_working_directory "$name" 2>/dev/null)"
    printf "unit     %s\n" "$(bigbrother_unit_path "$name")"
}

bigbrother_cmd_ls() {
    local name found=false
    local -a enabled_names=() disabled_names=() transient_names=()

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
    for n in "${transient_names[@]}"; do bigbrother_status_line '~' "$n"; done
    for n in "${enabled_names[@]}"; do bigbrother_status_line + "$n"; done
    for n in "${disabled_names[@]}"; do bigbrother_status_line - "$n"; done
}

# Promotes an already-running transient unit to a persisted one, and is the
# reason none of this resolves commands by hand: the ExecStart it reads back is
# the one systemd actually launched, so it carries systemd-run's absolute path
# resolution. Rebuilding that string from argv instead is what used to persist
# a bare name the manager's own PATH couldn't find — a unit that 203/EXEC'd
# forever despite having passed its own verification.
#
# The transient unit shadows any on-disk file of the same name, so it has to be
# fully stopped before the persistent unit can load.
bigbrother_promote_transient() {
    local name="$1" exec_start workdir
    exec_start=$(bigbrother_exec_start_command "$name") || {
        echo "bigbrother: could not read command from transient unit '$name'" >&2
        return 1
    }
    workdir=$(bigbrother_working_directory "$name")

    bigbrother_stop "$name" 2>/dev/null || true
    bigbrother_wait_stopped "$name" || {
        echo "bigbrother: transient '$name' did not stop; refusing to persist it" >&2
        return 1
    }
    bigbrother_reset_failed "$name"

    bigbrother_write_unit "$name" "$exec_start" "$workdir" || return 1
    bigbrother_daemon_reload
}

# `add` is `run` + `enable`. A name is mandatory — unlike an ad-hoc `run`, a
# persistent service is named deliberately rather than derived from whatever
# binary happened to start it.
bigbrother_cmd_add() {
    bigbrother_parse_launch_args name "$@" || return 1

    local name="$BB_ARG_NAME"
    [[ -n "$name" ]] || {
        echo "Usage: bigbrother add <name> [-c <command> [args...]] [--workdir <dir>]" >&2
        echo "bigbrother: a name is required; to run a path as a command use -c" >&2
        return 1
    }
    bigbrother_validate_name "$name" || return 1

    bigbrother_ensure_linger

    if ((${#BB_ARG_COMMAND[@]} > 0)); then
        bigbrother_add_verified "$name" "${BB_ARG_WORKDIR:-$PWD}" "${BB_ARG_COMMAND[@]}"
        return
    fi

    if bigbrother_is_defined "$name"; then
        echo "bigbrother: '$name' already exists" >&2
        return 1
    fi

    # No command given. Promote a running transient of this name if that's what
    # it is, otherwise open an empty draft for the caller to fill in.
    local body
    if bigbrother_is_transient "$name" 2>/dev/null; then
        local exec_start
        exec_start=$(bigbrother_exec_start_command "$name") || {
            echo "bigbrother: could not read command from transient unit '$name'" >&2
            return 1
        }
        body=$(bigbrother_render_unit "$name" "$exec_start" \
            "${BB_ARG_WORKDIR:-$(bigbrother_working_directory "$name")}")
        bigbrother_finalize_add "$name" "$body" "$name"
        return
    fi

    body=$(bigbrother_render_unit "$name" "" "${BB_ARG_WORKDIR:-$PWD}")
    bigbrother_finalize_add "$name" "$body"
}

# `bb add <name> -c <command> [args...]`: no editor. Runs the command as a
# transient unit and only persists it once bigbrother_verify_launch confirms it
# survived — the human "try it, then save it" pipeline, automated. The unit body
# comes from bigbrother_promote_transient reading the live unit back, never from
# rebuilding the command here; see that function for why that distinction is
# load-bearing.
bigbrother_add_verified() {
    local name="$1" workdir="$2"
    shift 2

    if bigbrother_name_taken "$name"; then
        echo "bigbrother: '$name' already exists" >&2
        return 1
    fi

    bigbrother_launch_transient "$name" "$workdir" "$@" || return 1
    bigbrother_promote_transient "$name" || return 1

    # The editor paths get this from bigbrother_edit_buffer; the -c path is the
    # one that would otherwise persist a unit nothing ever checked.
    bigbrother_verify_unit "$(bigbrother_unit_path "$name")" || {
        bigbrother_delete_unit "$name"
        bigbrother_daemon_reload
        return 1
    }

    bigbrother_enable_now "$name" || return 1
    bigbrother_status_line + "$name"
}

# Opens the editor draft, then writes + enables + starts the result.
bigbrother_finalize_add() {
    local suggested="$1" body="$2" promote_from="${3:-}"

    bigbrother_edit_buffer add "$suggested" "$body" || return 1
    local name="$BB_RESULT_NAME"

    if bigbrother_is_defined "$name"; then
        echo "bigbrother: '$name' already exists" >&2
        return 1
    fi

    if [[ -n "$promote_from" ]]; then
        bigbrother_stop "$promote_from" 2>/dev/null || true
        bigbrother_wait_stopped "$promote_from" || {
            echo "bigbrother: transient '$promote_from' did not stop; refusing to persist it" >&2
            return 1
        }
        bigbrother_reset_failed "$promote_from"
    fi

    bigbrother_write_unit_body "$name" "$BB_RESULT_BODY" || return 1
    bigbrother_daemon_reload
    bigbrother_enable_now "$name" || return 1
    bigbrother_status_line + "$name"
}

bigbrother_cmd_rm() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother rm <name>" >&2; return 1; }

    # A transient unit has no file to delete — stopping it *is* removing it.
    # Without this branch a name `ls` shows can't be removed at all.
    if ! bigbrother_is_defined "$name"; then
        if ! bigbrother_is_transient "$name" 2>/dev/null; then
            echo "bigbrother: '$name' is not defined" >&2
            return 1
        fi
        bigbrother_stop "$name" || {
            echo "bigbrother: failed to stop transient '$name'" >&2
            return 1
        }
        bigbrother_reset_failed "$name"
        bigbrother_status_line x "$name"
        return 0
    fi

    # Deleting the unit file while the service is still up would orphan the
    # process with nothing left to manage it, so the teardown is checked and
    # the file is kept on any failure rather than the status being swallowed.
    bigbrother_disable_now "$name" || {
        echo "bigbrother: failed to disable '$name'; unit file kept" >&2
        return 1
    }
    bigbrother_wait_stopped "$name" || {
        echo "bigbrother: '$name' did not stop; unit file kept" >&2
        return 1
    }
    bigbrother_reset_failed "$name"

    bigbrother_delete_unit "$name"
    bigbrother_daemon_reload
    bigbrother_status_line x "$name"
}

bigbrother_cmd_enable() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother enable <name>" >&2; return 1; }
    bigbrother_ensure_linger

    if ! bigbrother_is_defined "$name"; then
        if ! bigbrother_is_transient "$name" 2>/dev/null; then
            echo "bigbrother: '$name' is not defined" >&2
            echo "bigbrother: to define one: bigbrother add $name -c <command>" >&2
            return 1
        fi
        bigbrother_promote_transient "$name" || return 1
    fi

    bigbrother_enable_now "$name" || return 1
    bigbrother_status_line + "$name"
}

bigbrother_cmd_disable() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "Usage: bigbrother disable <name>" >&2; return 1; }
    bigbrother_is_defined "$name" || { echo "bigbrother: '$name' is not defined" >&2; return 1; }
    bigbrother_disable_now "$name"
    bigbrother_status_line - "$name"
}

bigbrother_cmd_run() {
    bigbrother_parse_launch_args command "$@" || return 1
    ((${#BB_ARG_COMMAND[@]} > 0)) || {
        echo "Usage: bigbrother run [-n <name>] <command> [args...]" >&2
        return 1
    }

    bigbrother_ensure_linger

    # The registry is consulted for exactly one shape: a lone, already-defined
    # name, meaning "start that service". Any further argument proves the input
    # is a command line, so a same-named service must not shadow it.
    if ((${#BB_ARG_COMMAND[@]} == 1)) && [[ -z "$BB_ARG_NAME" ]] &&
        bigbrother_is_defined "${BB_ARG_COMMAND[0]}"; then
        local defined="${BB_ARG_COMMAND[0]}"
        bigbrother_start "$defined" || return 1
        bigbrother_verify_launch "$defined" || return 1
        [[ "$BB_LAUNCH_STATE" == running ]] && bigbrother_status_line + "$defined"
        return 0
    fi

    local name
    if [[ -n "$BB_ARG_NAME" ]]; then
        bigbrother_validate_name "$BB_ARG_NAME" || return 1
        if bigbrother_name_taken "$BB_ARG_NAME"; then
            echo "bigbrother: '$BB_ARG_NAME' already exists" >&2
            return 1
        fi
        name="$BB_ARG_NAME"
    else
        # An explicit name must be honoured or refused; a derived one just steps
        # aside, so repeat runs of the same binary never collide.
        name=$(bigbrother_derive_name "${BB_ARG_COMMAND[0]}") || return 1
        name=$(bigbrother_free_name "$name") || return 1
    fi

    bigbrother_launch_transient "$name" "${BB_ARG_WORKDIR:-$PWD}" "${BB_ARG_COMMAND[@]}" || return 1
    [[ "$BB_LAUNCH_STATE" == running ]] && bigbrother_status_line '~' "$name"
    return 0
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
    bb <name>               Watch a running service's live output

Markers:
    + enabled   ~ transient (live)   - disabled   x removed

Commands:
    ls, list                List all services
    get, g <name>            Show details (status, command, workdir, unit path) for one service
    run [-n <name>] <cmd> [args...]
                              Run now as a transient unit and confirm it survived. Names itself
                              after the binary, appending .1/.2 when taken; -n names it outright.
                              A lone already-defined name instead just starts that service.
    add, a <name> -c <cmd> [args...]
                              run + enable: runs <cmd> transiently first and only persists it
                              if it survives. The saved command is read back off the unit that
                              actually ran, so it can never differ from the one verified.
    add, a <name>            No -c: opens $EDITOR on a unit draft, then defines + enables it.
                              Promotes a live transient of that name if one exists.
    rm, remove <name>        Stop, disable, and delete a service (or stop a transient)
    mv, rename <old> <new>   Rename a defined service, preserving its enabled/active state
    enable, up <name>        Enable + start; promotes a transient of that name first
    disable, down <name>     Disable + stop (definition kept)
    stop <name>               Stop now (stays defined)
    restart <name>
    watch, tail, attach <name>  Live view of the process output (same as `bb <name>`)
    logs <name> [-f] [--raw]  Past output; -f follows, --raw adds journald timestamps
    edit, e <name>             Opens $EDITOR on the unit; a changed 'bb-name' header renames it
    help, -h, --help

Both run and add take --workdir <dir>; the default is the directory you invoke from,
not wherever the binary happens to live. A path is just a command: pass it to -c.

All operations are systemd --user (no sudo).
EOF
}
