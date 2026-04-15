#!/usr/bin/env bash

port="$1"
if [[ -z "$port" ]]; then
    echo "Usage: get-port-process.sh <port_number>"
    exit 1
fi

result=$(lsof -i ":$port" -t 2>/dev/null | head -1)
if [[ -n "$result" ]]; then
    ps -p "$result" -o pid=,comm= | awk '{printf "PID %s: %s\n", $1, $2}'
else
    echo "Literally nothing on :$port"
fi
