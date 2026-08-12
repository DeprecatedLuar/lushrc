#!/usr/bin/env bash

CRONOTRIGGER_CONFIG_DIR="${CRONOTRIGGER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/cronotrigger}"
CRONOTRIGGER_ENABLED_FILE="$CRONOTRIGGER_CONFIG_DIR/.enabled"
CRONOTRIGGER_EXECUTION_DIR="$HOME"
CRONOTRIGGER_STATE_DIR="${CRONOTRIGGER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/cronotrigger}"
CRONOTRIGGER_LOG_DIR="$CRONOTRIGGER_STATE_DIR/logs"
CRONOTRIGGER_RUNTIME_DIR="${CRONOTRIGGER_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}/cronotrigger-${UID}}}"
CRONOTRIGGER_LOCK_DIR="$CRONOTRIGGER_RUNTIME_DIR/lock"

cronotrigger_init_paths() {
    if [[ "$CRONOTRIGGER_EXECUTION_DIR" != /* || ! -d "$CRONOTRIGGER_EXECUTION_DIR" ]]; then
        echo "cronotrigger: HOME must be an existing absolute directory" >&2
        return 1
    fi

    mkdir -p "$CRONOTRIGGER_CONFIG_DIR" "$CRONOTRIGGER_LOG_DIR" "$CRONOTRIGGER_RUNTIME_DIR" || {
        echo "cronotrigger: failed to initialize directories" >&2
        return 1
    }

    chmod 700 "$CRONOTRIGGER_CONFIG_DIR" "$CRONOTRIGGER_STATE_DIR" \
        "$CRONOTRIGGER_LOG_DIR" "$CRONOTRIGGER_RUNTIME_DIR" 2>/dev/null || true

    if [[ ! -e "$CRONOTRIGGER_ENABLED_FILE" ]]; then
        : > "$CRONOTRIGGER_ENABLED_FILE" || {
            echo "cronotrigger: cannot create $CRONOTRIGGER_ENABLED_FILE" >&2
            return 1
        }
        chmod 600 "$CRONOTRIGGER_ENABLED_FILE" 2>/dev/null || true
    elif [[ ! -f "$CRONOTRIGGER_ENABLED_FILE" ]]; then
        echo "cronotrigger: $CRONOTRIGGER_ENABLED_FILE is not a regular file" >&2
        return 1
    fi
}

cronotrigger_acquire_lock() {
    local owner_pid=""

    if mkdir "$CRONOTRIGGER_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$CRONOTRIGGER_LOCK_DIR/pid"
        return 0
    fi

    if [[ -r "$CRONOTRIGGER_LOCK_DIR/pid" ]]; then
        IFS= read -r owner_pid < "$CRONOTRIGGER_LOCK_DIR/pid" || true
    fi

    if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
        echo "cronotrigger: another operation is running (pid $owner_pid)" >&2
        return 1
    fi

    rm -f -- "$CRONOTRIGGER_LOCK_DIR/pid" 2>/dev/null || true
    if ! rmdir "$CRONOTRIGGER_LOCK_DIR" 2>/dev/null || ! mkdir "$CRONOTRIGGER_LOCK_DIR"; then
        echo "cronotrigger: failed to recover stale lock $CRONOTRIGGER_LOCK_DIR" >&2
        return 1
    fi

    printf '%s\n' "$$" > "$CRONOTRIGGER_LOCK_DIR/pid"
}

cronotrigger_release_lock() {
    local owner_pid=""

    [[ -d "$CRONOTRIGGER_LOCK_DIR" ]] || return 0
    if [[ -r "$CRONOTRIGGER_LOCK_DIR/pid" ]]; then
        IFS= read -r owner_pid < "$CRONOTRIGGER_LOCK_DIR/pid" || true
    fi
    if [[ "$owner_pid" == "$$" ]]; then
        rm -f -- "$CRONOTRIGGER_LOCK_DIR/pid"
        rmdir "$CRONOTRIGGER_LOCK_DIR" 2>/dev/null || true
    fi
}
