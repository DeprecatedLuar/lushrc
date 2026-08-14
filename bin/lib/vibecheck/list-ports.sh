#!/usr/bin/env bash

# Handle --all/-a flag for showing system services
if [[ "$1" == "--all" || "$1" == "-a" ]]; then
    if [[ $EUID -ne 0 ]]; then
        # Not root, re-execute with sudo
        exec sudo "$0"
    fi
fi

# docker-proxy listens on behalf of containers, so lsof/ps only ever show the
# truncated "docker-pr" command name — resolve it back to the container.
docker_ports=""
if command -v docker >/dev/null 2>&1; then
    docker_ports=$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null)
fi

resolve_docker_name() {
    local port="$1"
    [[ -z "$docker_ports" ]] && return
    awk -F'\t' -v p=":${port}->" '$2 ~ p { print $1; exit }' <<< "$docker_ports"
}

lsof -i -P -n | awk 'NR>1 && /LISTEN/ {
    split($9, a, ":")
    port = a[length(a)]
    if (!seen[port,$1]) {
        seen[port,$1] = 1
        print port " " $1
    }
}' | sort -n | while read -r port proc; do
    if [[ "$proc" == "docker-pr" ]]; then
        name=$(resolve_docker_name "$port")
        [[ -n "$name" ]] && proc="$name"
    fi
    printf '%5s (%s)\n' "$port" "$proc"
done
