#!/usr/bin/env bash

CRONOTRIGGER_DEFAULT_EVERY="day"
CRONOTRIGGER_DEFAULT_TIME="09:00"
CRONOTRIGGER_STATUS_ENABLED="enabled"
CRONOTRIGGER_STATUS_DISABLED="disabled"
CRONOTRIGGER_STATUS_INVALID="invalid"
CRONOTRIGGER_DIM=$'\033[2m'
CRONOTRIGGER_RESET=$'\033[0m'

cronotrigger_open_editor() {
    local path="$1" editor_value
    local -a editor_command=()

    editor_value="${VISUAL:-${EDITOR:-vi}}"
    read -r -a editor_command <<< "$editor_value"
    ((${#editor_command[@]} > 0)) || editor_command=(vi)
    "${editor_command[@]}" "$path"
}

cronotrigger_reconcile_or_rollback() {
    local rollback_function="$1"

    if cronotrigger_reconcile; then
        return 0
    fi

    echo "cronotrigger: update failed; rolling back configuration" >&2
    "$rollback_function" || echo "cronotrigger: rollback failed; configuration needs attention" >&2
    cronotrigger_reconcile >/dev/null 2>&1 || true
    return 1
}

cronotrigger_cmd_add() {
    local name="" initial_name="" path temp direct=false
    local every="" time_value="" command_value=""

    if (($# > 0)) && [[ "$1" != --* ]]; then
        initial_name="$1"
        shift
    fi

    while (($# > 0)); do
        direct=true
        case "$1" in
            --every)
                (($# >= 2)) || { echo "cronotrigger: --every requires a value" >&2; return 1; }
                every="$2"
                shift 2
                ;;
            --time)
                (($# >= 2)) || { echo "cronotrigger: --time requires a value" >&2; return 1; }
                time_value="$2"
                shift 2
                ;;
            --command)
                (($# >= 2)) || { echo "cronotrigger: --command requires a value" >&2; return 1; }
                command_value="$2"
                shift 2
                ;;
            *)
                echo "cronotrigger: unknown add option '$1'" >&2
                return 1
                ;;
        esac
    done

    if $direct; then
        [[ -n "$initial_name" && -n "$every" && -n "$command_value" ]] || {
            echo "cronotrigger: direct creation requires a name, --every, and --command" >&2
            return 1
        }
        name="$initial_name"
        JOB_EVERY="$every"
        JOB_TIME="$time_value"
        JOB_ANCHOR=""
        JOB_COMMAND="$command_value"
    else
        temp=$(mktemp "$CRONOTRIGGER_RUNTIME_DIR/add.XXXXXX") || return 1
        {
            printf 'name=%s\n' "$initial_name"
            printf 'every=%s\n' "$CRONOTRIGGER_DEFAULT_EVERY"
            printf 'time=%s\n' "$CRONOTRIGGER_DEFAULT_TIME"
            printf 'command=\n'
        } > "$temp"
        if ! cronotrigger_open_editor "$temp"; then
            rm -f -- "$temp"
            echo "cronotrigger: editor exited with an error" >&2
            return 1
        fi
        if ! cronotrigger_load_job "$temp" true; then
            rm -f -- "$temp"
            return 1
        fi
        name="$JOB_NAME"
        rm -f -- "$temp"
    fi

    [[ -n "$name" ]] || { echo "cronotrigger: name is required" >&2; return 1; }
    cronotrigger_validate_name "$name" || return 1
    path="$(cronotrigger_job_path "$name")"
    [[ ! -e "$path" ]] || {
        echo "cronotrigger: job '$name' already exists" >&2
        return 1
    }

    cronotrigger_finalize_job true || return 1
    cronotrigger_write_job "$path" || return 1
    if ! cronotrigger_set_enabled "$name" true; then
        rm -f -- "$path"
        return 1
    fi

    cronotrigger_rollback_add() {
        cronotrigger_set_enabled "$name" false
        rm -f -- "$path"
    }
    cronotrigger_reconcile_or_rollback cronotrigger_rollback_add || return 1
    unset -f cronotrigger_rollback_add

    echo "Added $name"
}

cronotrigger_cmd_edit() {
    local name="${1:-}" path temp backup old_every old_time regenerate=false

    [[ -n "$name" && $# -eq 1 ]] || { echo "Usage: cronotrigger edit <name>" >&2; return 1; }
    cronotrigger_validate_name "$name" || return 1
    path="$(cronotrigger_job_path "$name")"
    [[ -f "$path" ]] || { echo "cronotrigger: job '$name' does not exist" >&2; return 1; }

    old_every=""
    old_time=""
    if cronotrigger_load_job "$path" >/dev/null 2>&1; then
        old_every="$JOB_EVERY"
        old_time="$JOB_TIME"
    fi

    temp=$(mktemp "$CRONOTRIGGER_RUNTIME_DIR/edit.XXXXXX") || return 1
    backup=$(mktemp "$CRONOTRIGGER_RUNTIME_DIR/backup.XXXXXX") || { rm -f -- "$temp"; return 1; }
    cp "$path" "$temp"
    cp "$path" "$backup"

    if ! cronotrigger_open_editor "$temp"; then
        rm -f -- "$temp" "$backup"
        echo "cronotrigger: editor exited with an error" >&2
        return 1
    fi
    if ! cronotrigger_load_job "$temp"; then
        rm -f -- "$temp" "$backup"
        return 1
    fi
    [[ "$JOB_EVERY" != "$old_every" || "$JOB_TIME" != "$old_time" ]] && regenerate=true
    if ! cronotrigger_finalize_job "$regenerate"; then
        rm -f -- "$temp" "$backup"
        return 1
    fi
    rm -f -- "$temp"
    cronotrigger_write_job "$path" || { rm -f -- "$backup"; return 1; }

    cronotrigger_rollback_edit() {
        cp "$backup" "$path"
    }
    if ! cronotrigger_reconcile_or_rollback cronotrigger_rollback_edit; then
        rm -f -- "$backup"
        return 1
    fi
    unset -f cronotrigger_rollback_edit
    rm -f -- "$backup"
    echo "Updated $name"
}

cronotrigger_cmd_list() {
    local name path status schedule command_value found=false prefix="" suffix=""

    printf '%-24s %-10s %-24s %s\n' NAME STATUS SCHEDULE COMMAND
    while IFS= read -r name; do
        found=true
        path="$(cronotrigger_job_path "$name")"
        status="$CRONOTRIGGER_STATUS_DISABLED"
        cronotrigger_is_enabled "$name" && status="$CRONOTRIGGER_STATUS_ENABLED"

        if cronotrigger_validate_name "$name" >/dev/null 2>&1 && \
            cronotrigger_load_job "$path" >/dev/null 2>&1 && \
            cronotrigger_validate_job >/dev/null 2>&1; then
            schedule="$(cronotrigger_schedule_description)"
            command_value="$JOB_COMMAND"
        else
            status="$CRONOTRIGGER_STATUS_INVALID"
            schedule="-"
            command_value="-"
        fi

        prefix=""
        suffix=""
        if [[ "$status" == "$CRONOTRIGGER_STATUS_DISABLED" && -t 1 && -z "${NO_COLOR:-}" ]]; then
            prefix="$CRONOTRIGGER_DIM"
            suffix="$CRONOTRIGGER_RESET"
        fi
        printf '%s%-24s %-10s %-24s %s%s\n' "$prefix" "$name" "$status" "$schedule" "$command_value" "$suffix"
    done < <(cronotrigger_job_names)

    $found || echo "No jobs."
}

cronotrigger_cmd_set_enabled() {
    local name="${1:-}" desired="${2:-}" path previous backup=""

    [[ -n "$name" && $# -eq 2 ]] || { echo "cronotrigger: job name is required" >&2; return 1; }
    cronotrigger_validate_name "$name" || return 1
    path="$(cronotrigger_job_path "$name")"
    [[ -f "$path" ]] || { echo "cronotrigger: job '$name' does not exist" >&2; return 1; }

    previous=false
    cronotrigger_is_enabled "$name" && previous=true

    if [[ "$desired" == false && "$previous" == false ]]; then
        echo "$name is already $([[ "$desired" == true ]] && echo enabled || echo disabled)"
        return 0
    fi

    if [[ "$desired" == true ]]; then
        backup=$(mktemp "$CRONOTRIGGER_RUNTIME_DIR/enable.XXXXXX") || return 1
        cp "$path" "$backup"
        if ! cronotrigger_load_job "$path" || ! cronotrigger_finalize_job false || ! cronotrigger_write_job "$path"; then
            cp "$backup" "$path"
            rm -f -- "$backup"
            return 1
        fi
    fi

    if ! cronotrigger_set_enabled "$name" "$desired"; then
        [[ -z "$backup" ]] || cp "$backup" "$path"
        [[ -z "$backup" ]] || rm -f -- "$backup"
        return 1
    fi
    cronotrigger_rollback_enabled() {
        cronotrigger_set_enabled "$name" "$previous"
        [[ -z "$backup" ]] || cp "$backup" "$path"
    }
    if ! cronotrigger_reconcile_or_rollback cronotrigger_rollback_enabled; then
        [[ -z "$backup" ]] || rm -f -- "$backup"
        return 1
    fi
    unset -f cronotrigger_rollback_enabled
    [[ -z "$backup" ]] || rm -f -- "$backup"

    if [[ "$previous" == "$desired" ]]; then
        echo "$name is already enabled"
        return 0
    fi
    echo "$([[ "$desired" == true ]] && echo Enabled || echo Disabled) $name"
}

cronotrigger_cmd_remove() {
    local name="${1:-}" force=false path backup was_enabled=false answer

    [[ -n "$name" ]] || { echo "Usage: cronotrigger rm <name> [--force]" >&2; return 1; }
    shift
    if (($# > 0)); then
        [[ $# -eq 1 && "$1" == "--force" ]] || { echo "Usage: cronotrigger rm <name> [--force]" >&2; return 1; }
        force=true
    fi
    cronotrigger_validate_name "$name" || return 1
    path="$(cronotrigger_job_path "$name")"
    [[ -f "$path" ]] || { echo "cronotrigger: job '$name' does not exist" >&2; return 1; }

    if ! $force; then
        [[ -t 0 ]] || { echo "cronotrigger: use --force when removing non-interactively" >&2; return 1; }
        read -r -p "Remove '$name'? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled"; return 0; }
    fi

    backup=$(mktemp "$CRONOTRIGGER_RUNTIME_DIR/remove.XXXXXX") || return 1
    cp "$path" "$backup"
    cronotrigger_is_enabled "$name" && was_enabled=true
    cronotrigger_set_enabled "$name" false || { rm -f -- "$backup"; return 1; }
    rm -f -- "$path"

    cronotrigger_rollback_remove() {
        cp "$backup" "$path"
        cronotrigger_set_enabled "$name" "$was_enabled"
    }
    if ! cronotrigger_reconcile_or_rollback cronotrigger_rollback_remove; then
        rm -f -- "$backup"
        return 1
    fi
    unset -f cronotrigger_rollback_remove
    rm -f -- "$backup"
    echo "Removed $name"
}

cronotrigger_cmd_run() {
    local name="${1:-}"
    [[ -n "$name" && $# -eq 1 ]] || { echo "Usage: cronotrigger run <name>" >&2; return 1; }
    cronotrigger_run_job "$name" manual
}

cronotrigger_cmd_help() {
    cat <<'EOF'
cronotrigger - human-friendly recurring command scheduler

Usage:
  cronotrigger add|a
  cronotrigger add|a <name>
  cronotrigger add|a <name> --every <schedule> [--time HH:MM] --command <command>
  cronotrigger edit|e <name>
  cronotrigger list|ls
  cronotrigger enable <name>
  cronotrigger disable <name>
  cronotrigger run <name>
  cronotrigger remove|rm <name> [--force]

Schedules:
  day, d, 1d       Every day; requires --time
  6d               Every six days from the stored anchor; requires --time
  mon,wed,fri      Selected weekdays; requires --time
  1st,15th         Selected days of the month; requires --time
  hour, h, 1h      Every hour from the stored anchor
  6h               Every six hours from the stored anchor

Job file fields:
  name              Creation drafts only. Becomes <name>.job and is not stored.
  every             Required schedule using one of the forms above.
  time              Required for day, Nd, weekday, and ordinal schedules.
  anchor            Managed automatically for Nd and Nh schedules. Do not add it.
  command           Required Bash command.

Creation draft example:
  name=monthly-report
  every=1st
  time=09:00
  command=/home/user/scripts/monthly-report.sh

Stored job example (monthly-report.job):
  every=1st
  time=09:00
  command=/home/user/scripts/monthly-report.sh

Commands always run from the user's home directory. Use absolute paths for
files and scripts referenced by command. Executables may still be resolved
through PATH. Job files accept no other keys.

Every user-facing invocation validates the job store and reconciles its managed
crontab block. New jobs are enabled by default. Manually created .job files are
disabled until explicitly enabled.
EOF
}
