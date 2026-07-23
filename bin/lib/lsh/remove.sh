#!/usr/bin/env bash
# lsh remove/rm — delete an SSH config entry from ~/.ssh/config.d/lsh

lsh_remove() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: lsh remove <name>" >&2
        return 1
    fi

    local NAME="$1"
    local LSH_CONFIG="$HOME/.ssh/config.d/lsh"

    [[ -f "$LSH_CONFIG" ]] || { echo "lsh remove: no entries found ($LSH_CONFIG missing)" >&2; return 1; }

    local found=false
    local TMP
    TMP=$(mktemp)
    local in_block=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$NAME" ]]; then
                in_block=true
                found=true
                continue
            else
                in_block=false
            fi
        fi
        $in_block && continue
        echo "$line" >> "$TMP"
    done < "$LSH_CONFIG"

    if ! $found; then
        rm -f "$TMP"
        echo "lsh remove: no entry named '$NAME' in $LSH_CONFIG" >&2
        return 1
    fi

    mv "$TMP" "$LSH_CONFIG"
    chmod 600 "$LSH_CONFIG"

    echo "Removed: $NAME"
}
