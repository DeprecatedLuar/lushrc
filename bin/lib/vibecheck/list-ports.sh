#!/usr/bin/env bash

# Handle --all/-a flag for showing system services
if [[ "$1" == "--all" || "$1" == "-a" ]]; then
    if [[ $EUID -ne 0 ]]; then
        # Not root, re-execute with sudo
        exec sudo "$0"
    fi
fi

lsof -i -P -n | awk 'NR>1 && /LISTEN/ {
    split($9, a, ":")
    port = a[length(a)]
    if (!seen[port,$2]) {
        seen[port,$2] = 1
        print port " (" $1 ")"
    }
}' | sort -n
