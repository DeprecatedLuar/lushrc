#!/usr/bin/env bash

# Unit file template render, write, delete.

BIGBROTHER_UNIT_TEMPLATE='[Unit]
Description=%s

[Service]
ExecStart=%s
WorkingDirectory=%s
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
'

bigbrother_write_unit() {
    local name="$1" exec_start="$2" workdir="$3" path
    path=$(bigbrother_unit_path "$name")

    # shellcheck disable=SC2059
    printf "$BIGBROTHER_UNIT_TEMPLATE" "$name" "$exec_start" "$workdir" > "$path" || {
        echo "bigbrother: failed to write $path" >&2
        return 1
    }
}

bigbrother_delete_unit() {
    rm -f -- "$(bigbrother_unit_path "$1")"
}
