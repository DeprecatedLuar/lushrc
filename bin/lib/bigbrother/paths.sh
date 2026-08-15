#!/usr/bin/env bash

BIGBROTHER_UNIT_DIR="${BIGBROTHER_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
BIGBROTHER_RUNTIME_DIR="${BIGBROTHER_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}/bigbrother-${UID}}}"
BIGBROTHER_DRAFT_DIR="$BIGBROTHER_RUNTIME_DIR/drafts"

# Under systemd a service's stdout is a journald pipe, not a TTY, so programs
# disable their own color. journald itself stores and replays ANSI bytes
# untouched — these are the widely-honored opt-ins that turn color back on.
BIGBROTHER_SERVICE_ENV=(FORCE_COLOR=1 CLICOLOR_FORCE=1 PY_COLORS=1)

# /run/systemd/system only exists when systemd is actually PID 1 — the
# canonical check, since `command -v systemctl` can pass under other inits.
bigbrother_require_systemd() {
    [[ -d /run/systemd/system ]] || {
        echo "bigbrother: systemd is not running on this machine (no /run/systemd/system)." >&2
        echo "bigbrother: this tool only works as a systemd --user wrapper." >&2
        return 1
    }
    command -v systemctl &>/dev/null || {
        echo "bigbrother: systemctl not found on PATH" >&2
        return 1
    }
}

bigbrother_init_paths() {
    mkdir -p "$BIGBROTHER_UNIT_DIR" "$BIGBROTHER_DRAFT_DIR" || {
        echo "bigbrother: failed to create bigbrother directories" >&2
        return 1
    }
    chmod 700 "$BIGBROTHER_RUNTIME_DIR" "$BIGBROTHER_DRAFT_DIR" 2>/dev/null || true
}

bigbrother_unit_path() {
    printf '%s/%s.service\n' "$BIGBROTHER_UNIT_DIR" "$1"
}
