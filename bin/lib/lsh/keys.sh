#!/usr/bin/env bash
# lsh keys — list SSH keys under ~/.ssh/private and ~/.ssh/public

lsh_keys() {
    local FILTER="${1:-}"
    if [[ -n "$FILTER" && "$FILTER" != "pub" && "$FILTER" != "priv" ]]; then
        echo "Usage: lsh keys [pub|priv]" >&2
        return 1
    fi

    if [[ "$FILTER" != "pub" ]]; then
        echo "Private:"
        ls -1 ~/.ssh/private 2>/dev/null | sed 's/^/  /'
    fi

    if [[ "$FILTER" != "priv" ]]; then
        [[ -z "$FILTER" ]] && echo
        echo "Public:"
        ls -1 ~/.ssh/public 2>/dev/null | sed 's/^/  /'
    fi
}
