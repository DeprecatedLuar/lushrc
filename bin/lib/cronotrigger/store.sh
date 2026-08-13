#!/usr/bin/env bash

CRONOTRIGGER_JOB_SUFFIX=".job"
CRONOTRIGGER_NAME_PATTERN='^[a-z0-9][a-z0-9._-]*$'

cronotrigger_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

cronotrigger_validate_name() {
    local name="$1"

    if [[ ! "$name" =~ $CRONOTRIGGER_NAME_PATTERN ]]; then
        echo "cronotrigger: invalid job name '$name' (use lowercase letters, numbers, ., _, or -)" >&2
        return 1
    fi
}

cronotrigger_job_path() {
    printf '%s/%s%s\n' "$CRONOTRIGGER_CONFIG_DIR" "$1" "$CRONOTRIGGER_JOB_SUFFIX"
}

cronotrigger_job_names() {
    local path name
    local -a paths=()

    shopt -s nullglob
    paths=("$CRONOTRIGGER_CONFIG_DIR"/*"$CRONOTRIGGER_JOB_SUFFIX")
    shopt -u nullglob

    ((${#paths[@]} > 0)) || return 0
    for path in "${paths[@]}"; do
        name="${path##*/}"
        name="${name%$CRONOTRIGGER_JOB_SUFFIX}"
        printf '%s\n' "$name"
    done | LC_ALL=C sort
}

cronotrigger_reset_job() {
    JOB_NAME=""
    JOB_EVERY=""
    JOB_TIME=""
    JOB_ANCHOR=""
    JOB_COMMAND=""
}

cronotrigger_load_job() {
    local path="$1"
    local allow_name="${2:-false}"
    local display="${3:-$path}"
    local line line_number=0 key value
    local seen_name=false seen_every=false seen_time=false seen_anchor=false
    local seen_command=false

    cronotrigger_reset_job
    [[ -f "$path" ]] || {
        echo "cronotrigger: job file not found: $display" >&2
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" != *"="* ]]; then
            echo "cronotrigger: $display:$line_number: expected key=value" >&2
            return 1
        fi

        key="$(cronotrigger_trim "${line%%=*}")"
        value="$(cronotrigger_trim "${line#*=}")"

        case "$key" in
            name)
                if [[ "$allow_name" != true ]]; then
                    echo "cronotrigger: $display:$line_number: name is only valid in a new-job draft" >&2
                    return 1
                fi
                $seen_name && { echo "cronotrigger: $display:$line_number: duplicate key 'name'" >&2; return 1; }
                JOB_NAME="$value"
                seen_name=true
                ;;
            every)
                $seen_every && { echo "cronotrigger: $display:$line_number: duplicate key 'every'" >&2; return 1; }
                JOB_EVERY="$value"
                seen_every=true
                ;;
            time)
                $seen_time && { echo "cronotrigger: $display:$line_number: duplicate key 'time'" >&2; return 1; }
                JOB_TIME="$value"
                seen_time=true
                ;;
            anchor)
                $seen_anchor && { echo "cronotrigger: $display:$line_number: duplicate key 'anchor'" >&2; return 1; }
                JOB_ANCHOR="$value"
                seen_anchor=true
                ;;
            command)
                $seen_command && { echo "cronotrigger: $display:$line_number: duplicate key 'command'" >&2; return 1; }
                JOB_COMMAND="$value"
                seen_command=true
                ;;
            *)
                echo "cronotrigger: $display:$line_number: unknown key '$key'" >&2
                return 1
                ;;
        esac
    done < "$path"
}

cronotrigger_draft_path() {
    printf '%s/%s%s\n' "$CRONOTRIGGER_DRAFT_DIR" "$1" "$CRONOTRIGGER_JOB_SUFFIX"
}

cronotrigger_stash_draft() {
    local temp="$1" name="$2"

    [[ -n "$name" ]] || return 0
    cronotrigger_validate_name "$name" >/dev/null 2>&1 || return 0
    mkdir -p "$CRONOTRIGGER_DRAFT_DIR" 2>/dev/null || return 0
    cp -- "$temp" "$(cronotrigger_draft_path "$name")" 2>/dev/null || return 0
    chmod 600 "$(cronotrigger_draft_path "$name")" 2>/dev/null || true
}

cronotrigger_discard_draft() {
    local name="$1"

    [[ -n "$name" ]] || return 0
    rm -f -- "$(cronotrigger_draft_path "$name")" 2>/dev/null || true
}

cronotrigger_write_job() {
    local path="$1"
    local temp

    temp=$(mktemp "$CRONOTRIGGER_CONFIG_DIR/.job.tmp.XXXXXX") || {
        echo "cronotrigger: failed to create temporary job file" >&2
        return 1
    }

    {
        printf 'every=%s\n' "$JOB_EVERY"
        [[ -n "$JOB_TIME" ]] && printf 'time=%s\n' "$JOB_TIME"
        [[ -n "$JOB_ANCHOR" ]] && printf 'anchor=%s\n' "$JOB_ANCHOR"
        printf 'command=%s\n' "$JOB_COMMAND"
    } > "$temp" || {
        rm -f -- "$temp"
        echo "cronotrigger: failed to write temporary job file" >&2
        return 1
    }

    chmod 600 "$temp" 2>/dev/null || true
    if ! mv -f -- "$temp" "$path"; then
        rm -f -- "$temp"
        echo "cronotrigger: failed to install job file $path" >&2
        return 1
    fi
}

cronotrigger_is_enabled() {
    local name="$1"
    grep -Fqx -- "$name" "$CRONOTRIGGER_ENABLED_FILE" 2>/dev/null
}

cronotrigger_set_enabled() {
    local name="$1" desired="$2"
    local temp

    temp=$(mktemp "$CRONOTRIGGER_CONFIG_DIR/.enabled.tmp.XXXXXX") || {
        echo "cronotrigger: failed to create temporary enabled manifest" >&2
        return 1
    }

    if [[ "$desired" == true ]]; then
        if ! { sed '/^[[:space:]]*$/d' "$CRONOTRIGGER_ENABLED_FILE"; printf '%s\n' "$name"; } |
            LC_ALL=C sort -u > "$temp"; then
            rm -f -- "$temp"
            echo "cronotrigger: failed to prepare enabled manifest" >&2
            return 1
        fi
    else
        if ! awk -v target="$name" '$0 != target && $0 !~ /^[[:space:]]*$/' \
            "$CRONOTRIGGER_ENABLED_FILE" > "$temp"; then
            rm -f -- "$temp"
            echo "cronotrigger: failed to prepare enabled manifest" >&2
            return 1
        fi
    fi

    chmod 600 "$temp" 2>/dev/null || true
    if ! mv -f -- "$temp" "$CRONOTRIGGER_ENABLED_FILE"; then
        rm -f -- "$temp"
        echo "cronotrigger: failed to update enabled manifest" >&2
        return 1
    fi
}

cronotrigger_prune_enabled() {
    local temp name path changed=false

    temp=$(mktemp "$CRONOTRIGGER_CONFIG_DIR/.enabled.tmp.XXXXXX") || {
        echo "cronotrigger: failed to create temporary enabled manifest" >&2
        return 1
    }

    while IFS= read -r name || [[ -n "$name" ]]; do
        name="$(cronotrigger_trim "$name")"
        [[ -z "$name" ]] && continue
        if ! cronotrigger_validate_name "$name" >/dev/null 2>&1; then
            echo "cronotrigger: removing invalid .enabled entry '$name'" >&2
            changed=true
            continue
        fi
        path="$(cronotrigger_job_path "$name")"
        if [[ ! -f "$path" ]]; then
            echo "cronotrigger: removing orphaned .enabled entry '$name'" >&2
            changed=true
            continue
        fi
        printf '%s\n' "$name"
    done < "$CRONOTRIGGER_ENABLED_FILE" | LC_ALL=C sort -u > "$temp"

    if ! cmp -s "$CRONOTRIGGER_ENABLED_FILE" "$temp"; then
        changed=true
    fi

    if $changed; then
        chmod 600 "$temp" 2>/dev/null || true
        mv -f -- "$temp" "$CRONOTRIGGER_ENABLED_FILE" || {
            rm -f -- "$temp"
            echo "cronotrigger: failed to repair enabled manifest" >&2
            return 1
        }
    else
        rm -f -- "$temp"
    fi
}
