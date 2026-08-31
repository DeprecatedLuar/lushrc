#!/usr/bin/env bash

BIGBROTHER_UNIT_DIR="${BIGBROTHER_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
BIGBROTHER_RUNTIME_DIR="${BIGBROTHER_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}/bigbrother-${UID}}}"
BIGBROTHER_DRAFT_DIR="$BIGBROTHER_RUNTIME_DIR/drafts"

# PATH is set explicitly rather than left to the systemd --user manager's own
# environment: systemd-run only inherits the manager's ambient env plus
# --setenv, never the invoking shell's. On a machine where nothing ever
# imported a full PATH into that manager (e.g. a headless box with no
# graphical/interactive session), a bare command name resolves against the
# manager's near-empty PATH and 203/EXECs. Carrying the launching shell's own
# PATH here makes resolution machine-independent instead of depending on
# ambient state.
BIGBROTHER_SERVICE_ENV=("PATH=$PATH")

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
