#!/usr/bin/env bash

lsof -i -P -n | awk 'NR>1 && /LISTEN/ {
    split($9, a, ":")
    port = a[length(a)]
    if (!seen[port,$2]) {
        seen[port,$2] = 1
        print port " (" $1 ")"
    }
}' | sort -n
