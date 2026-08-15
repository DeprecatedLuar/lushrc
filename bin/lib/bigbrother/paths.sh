#!/usr/bin/env bash

BIGBROTHER_UNIT_DIR="${BIGBROTHER_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"

bigbrother_init_paths() {
    mkdir -p "$BIGBROTHER_UNIT_DIR" || {
        echo "bigbrother: failed to create $BIGBROTHER_UNIT_DIR" >&2
        return 1
    }
}

bigbrother_unit_path() {
    printf '%s/%s.service\n' "$BIGBROTHER_UNIT_DIR" "$1"
}
