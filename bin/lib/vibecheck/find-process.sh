#!/usr/bin/env bash

if [[ "$1" == "-p" ]]; then
    pid="$2"
    if [[ -z "$pid" ]]; then
        echo "Usage: find-process.sh -p <pid>"
        exit 1
    fi

    if ps -p "$pid" &>/dev/null; then
        comm=$(ps -p "$pid" -o comm= 2>/dev/null)
        cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | xargs | awk '{printf "%.0f", $1}')
        mem=$(ps -p "$pid" -o %mem= 2>/dev/null | xargs | awk '{printf "%.0f", $1}')
        cmd=$(ps -p "$pid" -o args= 2>/dev/null)

        echo "$pid ($comm)"
        echo "CPU ${cpu}% | RAM ${mem}%"
        echo "$cmd"
        exit 0
    else
        exit 1
    fi
else
    name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: find-process.sh <process_name>"
        exit 1
    fi

    pids=$(pgrep -i "$name" 2>/dev/null || pgrep "$name")

    if [[ -z "$pids" ]]; then
        pids=$(pgrep -f "$name")
    fi

    if [[ -z "$pids" ]]; then
        pids=$(ps -eo pid,comm --no-headers | fzf --filter="$name" -1 | awk '{print $1}')
    fi

    if [[ -n "$pids" ]]; then
        echo "$pids" | while read -r pid; do
            comm=$(ps -p "$pid" -o comm= 2>/dev/null || ps -o pid,comm | awk "\$1 == $pid {print \$2}")
            [[ -n "$comm" ]] && echo "$comm ($pid)"
        done
    fi

    exit 0
fi
