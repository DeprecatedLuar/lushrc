#!/usr/bin/env bash
# lsh get — show details for a single SSH config entry
#   lsh get <name>

lsh_get() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: lsh get <name>" >&2
        return 1
    fi
    local NAME="$1"

    local name endpoint host port user
    while IFS=$'\t' read -r name endpoint host port; do
        [[ "$name" == "$NAME" ]] || continue
        user=""
        [[ "$endpoint" == *@* ]] && user="${endpoint%%@*}"
        printf "name  %s\n" "$name"
        printf "host  %s\n" "$host"
        [[ -n "$user" ]] && printf "user  %s\n" "$user"
        printf "port  %s\n" "$port"
        return 0
    done < <(lsh_list_entries)

    echo "lsh get: no entry named '$NAME'" >&2
    return 1
}
