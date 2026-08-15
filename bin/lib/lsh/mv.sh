#!/usr/bin/env bash
# lsh mv/rename — rename an existing SSH config entry in ~/.ssh/config.d/lsh

lsh_mv() {
    if [[ $# -ne 2 ]]; then
        echo "Usage: lsh mv <name> <newname>" >&2
        return 1
    fi

    local NAME="$1" NEW_NAME="$2"
    local LSH_CONFIG="$HOME/.ssh/config.d/lsh"

    [[ -f "$LSH_CONFIG" ]] || { echo "lsh mv: no entries found ($LSH_CONFIG missing)" >&2; return 1; }

    local found=false
    local TMP
    TMP=$(mktemp)
    while IFS= read -r line; do
        if [[ "$line" =~ ^([Hh]ost[[:space:]]+)(.+)$ ]] && [[ "${BASH_REMATCH[2]}" == "$NAME" ]]; then
            found=true
            echo "${BASH_REMATCH[1]}$NEW_NAME" >> "$TMP"
            continue
        fi
        echo "$line" >> "$TMP"
    done < "$LSH_CONFIG"

    if ! $found; then
        rm -f "$TMP"
        echo "lsh mv: no entry named '$NAME' in $LSH_CONFIG" >&2
        return 1
    fi

    mv "$TMP" "$LSH_CONFIG"
    chmod 600 "$LSH_CONFIG"

    echo "Renamed: $NAME → $NEW_NAME"
}
