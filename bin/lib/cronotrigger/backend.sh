#!/usr/bin/env bash

CRONOTRIGGER_BLOCK_BEGIN="# BEGIN cronotrigger"
CRONOTRIGGER_BLOCK_END="# END cronotrigger"
CRONOTRIGGER_CRONTAB_COMMAND="${CRONOTRIGGER_CRONTAB_COMMAND:-crontab}"

cronotrigger_shell_quote() {
    local value="$1"
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

cronotrigger_cron_command() {
    local name="$1" command log_path

    log_path="$CRONOTRIGGER_LOG_DIR/$name.log"
    command="PATH=$(cronotrigger_shell_quote "$CRONOTRIGGER_EXEC_PATH")"
    command+=" $(cronotrigger_shell_quote "$CRONOTRIGGER_BASH_BIN")"
    command+=" $(cronotrigger_shell_quote "$CRONOTRIGGER_BIN") _run $(cronotrigger_shell_quote "$name")"
    command+=" >> $(cronotrigger_shell_quote "$log_path") 2>&1"
    command="${command//%/\\%}"
    printf '%s\n' "$command"
}

cronotrigger_build_entries() {
    local name path command

    while IFS= read -r name; do
        cronotrigger_validate_name "$name" >/dev/null 2>&1 || {
            echo "cronotrigger: ignoring invalid job filename '$name$CRONOTRIGGER_JOB_SUFFIX'" >&2
            continue
        }
        cronotrigger_is_enabled "$name" || continue

        path="$(cronotrigger_job_path "$name")"
        if ! cronotrigger_load_job "$path" || ! cronotrigger_validate_job; then
            echo "cronotrigger: enabled job '$name' is invalid and was not scheduled" >&2
            continue
        fi
        cronotrigger_compile_schedule || {
            echo "cronotrigger: enabled job '$name' could not be compiled" >&2
            continue
        }

        command="$(cronotrigger_cron_command "$name")"
        printf '%s %s # cronotrigger:%s\n' "$CRON_SPEC" "$command" "$name"
    done < <(cronotrigger_job_names)
}

cronotrigger_read_crontab() {
    local output_path="$1" error_path="$2" status

    if ! command -v "$CRONOTRIGGER_CRONTAB_COMMAND" >/dev/null 2>&1; then
        echo "cronotrigger: crontab command not found" >&2
        return 1
    fi

    LC_ALL=C "$CRONOTRIGGER_CRONTAB_COMMAND" -l > "$output_path" 2> "$error_path" && return 0
    status=$?

    if grep -Eqi 'no crontab|no crontab for|does not exist' "$error_path"; then
        : > "$output_path"
        return 0
    fi

    echo "cronotrigger: failed to read crontab (exit $status)" >&2
    sed 's/^/cronotrigger: /' "$error_path" >&2
    return 1
}

cronotrigger_reconcile() {
    local temp_dir current errors entries unmanaged candidate verify verify_errors
    local begin_count end_count begin_line end_line

    temp_dir=$(mktemp -d "$CRONOTRIGGER_RUNTIME_DIR/reconcile.XXXXXX") || {
        echo "cronotrigger: failed to create reconciliation workspace" >&2
        return 1
    }
    current="$temp_dir/current"
    errors="$temp_dir/errors"
    entries="$temp_dir/entries"
    unmanaged="$temp_dir/unmanaged"
    candidate="$temp_dir/candidate"
    verify="$temp_dir/verify"
    verify_errors="$temp_dir/verify-errors"

    if ! cronotrigger_read_crontab "$current" "$errors"; then
        rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
        rmdir "$temp_dir" 2>/dev/null || true
        return 1
    fi

    begin_count=$(grep -Fxc "$CRONOTRIGGER_BLOCK_BEGIN" "$current" || true)
    end_count=$(grep -Fxc "$CRONOTRIGGER_BLOCK_END" "$current" || true)
    if [[ "$begin_count" != "$end_count" || "$begin_count" -gt 1 ]]; then
        echo "cronotrigger: malformed managed block in crontab; refusing to modify it" >&2
        rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
        rmdir "$temp_dir" 2>/dev/null || true
        return 1
    fi
    if [[ "$begin_count" -eq 1 ]]; then
        begin_line=$(grep -Fnx "$CRONOTRIGGER_BLOCK_BEGIN" "$current" | cut -d: -f1)
        end_line=$(grep -Fnx "$CRONOTRIGGER_BLOCK_END" "$current" | cut -d: -f1)
        if ((begin_line >= end_line)); then
            echo "cronotrigger: malformed managed block in crontab; refusing to modify it" >&2
            rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
            rmdir "$temp_dir" 2>/dev/null || true
            return 1
        fi
    fi

    cronotrigger_build_entries > "$entries"
    awk -v begin="$CRONOTRIGGER_BLOCK_BEGIN" -v end="$CRONOTRIGGER_BLOCK_END" '
        $0 == begin { inside = 1; next }
        $0 == end { inside = 0; next }
        !inside { print }
    ' "$current" > "$unmanaged"

    cp "$unmanaged" "$candidate"
    if [[ -s "$entries" ]]; then
        printf '%s\n' "$CRONOTRIGGER_BLOCK_BEGIN" >> "$candidate"
        cat "$entries" >> "$candidate"
        printf '%s\n' "$CRONOTRIGGER_BLOCK_END" >> "$candidate"
    fi

    if cmp -s "$current" "$candidate"; then
        rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
        rmdir "$temp_dir" 2>/dev/null || true
        return 0
    fi

    if ! cronotrigger_read_crontab "$verify" "$verify_errors" || ! cmp -s "$current" "$verify"; then
        echo "cronotrigger: crontab changed during reconciliation; try again" >&2
        rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
        rmdir "$temp_dir" 2>/dev/null || true
        return 1
    fi

    if ! LC_ALL=C "$CRONOTRIGGER_CRONTAB_COMMAND" "$candidate"; then
        echo "cronotrigger: failed to install reconciled crontab" >&2
        rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
        rmdir "$temp_dir" 2>/dev/null || true
        return 1
    fi

    rm -f -- "$current" "$errors" "$entries" "$unmanaged" "$candidate" "$verify" "$verify_errors"
    rmdir "$temp_dir" 2>/dev/null || true
}

cronotrigger_self_heal() {
    cronotrigger_prune_enabled || return 1
    cronotrigger_reconcile
}
