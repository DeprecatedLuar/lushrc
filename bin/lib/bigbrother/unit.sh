#!/usr/bin/env bash

# Unit file template render, write, delete.

BIGBROTHER_UNIT_TEMPLATE='[Unit]
Description=%s

[Service]
ExecStart=%s
WorkingDirectory=%s
Environment=%s
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
'

bigbrother_render_unit() {
    local name="$1" exec_start="$2" workdir="$3"
    # shellcheck disable=SC2059
    printf "$BIGBROTHER_UNIT_TEMPLATE" \
        "$name" "$exec_start" "$workdir" "${BIGBROTHER_SERVICE_ENV[*]}"
}

bigbrother_write_unit() {
    local name="$1"
    bigbrother_write_unit_body "$name" "$(bigbrother_render_unit "$@")"
}

bigbrother_write_unit_body() {
    local name="$1" body="$2" path
    path=$(bigbrother_unit_path "$name")
    printf '%s\n' "$body" > "$path" || {
        echo "bigbrother: failed to write $path" >&2
        return 1
    }
}

bigbrother_delete_unit() {
    rm -f -- "$(bigbrother_unit_path "$1")"
}

# bb's own identity field lives in a header line stripped before the body
# ever touches disk or systemd-analyze — see bigbrother_edit_buffer.
BIGBROTHER_NAME_PATTERN='^[a-z0-9][a-z0-9._-]*$'

bigbrother_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

bigbrother_validate_name() {
    local name="$1"
    if [[ ! "$name" =~ $BIGBROTHER_NAME_PATTERN ]]; then
        echo "bigbrother: invalid name '$name' (use lowercase letters, numbers, ., _, or -)" >&2
        return 1
    fi
}

# Reduces systemd-analyze's raw verify output to one plain-English line per
# problem: drops the redundant "Unit X has a bad unit file setting." wrapper,
# and strips the temp-file path down to just its line number.
bigbrother_verify_unit() {
    local file="$1" output status=0 line
    output=$(systemd-analyze --user verify "$file" 2>&1) || status=$?
    ((status == 0)) && return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^Unit\ .*\ unit\ file\ setting\.$ ]] && continue
        if [[ "$line" =~ ^[^:]+:([0-9]+):\ (.*)$ ]]; then
            line="line ${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[^:]+\.service:\ (.*)$ ]]; then
            line="${BASH_REMATCH[1]}"
        fi
        echo "bigbrother: $line" >&2
    done <<< "$output"
    return 1
}

bigbrother_draft_path() {
    printf '%s/%s-%s.draft\n' "$BIGBROTHER_DRAFT_DIR" "$1" "$2"
}

bigbrother_stash_draft() {
    local temp="$1" mode="$2" name="$3" draft
    draft=$(bigbrother_draft_path "$mode" "$name")
    cp -- "$temp" "$draft" 2>/dev/null || return 0
    chmod 600 "$draft" 2>/dev/null || true
}

bigbrother_discard_draft() {
    rm -f -- "$(bigbrother_draft_path "$1" "$2")" 2>/dev/null || true
}

# Renames a defined unit's identity on disk, preserving its enabled/active
# state across the move. `old`'s unit file is expected to already hold
# whatever body content should end up at `new`.
bigbrother_rename_unit() {
    local old="$1" new="$2" was_enabled=false was_active=false

    bigbrother_is_defined "$new" && { echo "bigbrother: '$new' already exists" >&2; return 1; }

    bigbrother_is_enabled "$old" && was_enabled=true
    bigbrother_is_running "$old" && was_active=true

    bigbrother_stop "$old" 2>/dev/null || true
    bigbrother_disable_now "$old" 2>/dev/null || true

    mv -- "$(bigbrother_unit_path "$old")" "$(bigbrother_unit_path "$new")" || {
        echo "bigbrother: failed to rename unit file" >&2
        return 1
    }
    bigbrother_daemon_reload

    if $was_enabled; then
        bigbrother_enable_now "$new"
    elif $was_active; then
        bigbrother_start "$new"
    fi
}
