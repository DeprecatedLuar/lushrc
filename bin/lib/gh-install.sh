#!/usr/bin/env bash
# gh-install - ensure a GitHub-hosted binary is installed via the-satellite
# Usage: gh_install <binary> <user/repo>

gh_install() {
    local binary="$1"
    local repo="$2"

    local real
    real="$(which -a "$binary" 2>/dev/null | grep -v "^$BASHRC" | head -1)"

    if [[ ! -x "$real" ]]; then
        echo "$binary: not found, installing..." >&2
        curl -sSL "https://raw.githubusercontent.com/DeprecatedLuar/the-satellite/main/satellite.sh" | \
            bash -s -- install "$repo"
        real="$(which -a "$binary" 2>/dev/null | grep -v "^$BASHRC" | head -1)"
    fi

    exec "$real" "${@:3}"
}
