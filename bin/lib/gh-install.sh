#!/usr/bin/env bash
# gh-install - ensure a GitHub-hosted binary is installed via the-satellite
# Usage: gh_install <binary> <user/repo>

gh_install() {
    local binary="$1"
    local repo="$2"

    local real_home="$HOME"
    [[ -n "$SUDO_USER" ]] && real_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    local -a search_paths=("$real_home/bin" "$real_home/.local/bin" /usr/local/bin /usr/bin /bin)
    local real

    _find_binary() {
        real="$(which -a "$binary" 2>/dev/null | grep -v "^$BASHRC" | head -1)"
        if [[ ! -x "$real" ]]; then
            for dir in "${search_paths[@]}"; do
                [[ -x "$dir/$binary" ]] && real="$dir/$binary" && return
            done
        fi
    }

    _find_binary

    if [[ ! -x "$real" ]]; then
        echo "$binary: not found, installing..." >&2
        curl -sSL "https://raw.githubusercontent.com/DeprecatedLuar/the-satellite/main/satellite.sh" | \
            bash -s -- install "$repo"
        _find_binary
    fi

    [[ -x "$real" ]] || { echo "$binary: could not find binary after install" >&2; return 1; }
    exec "$real" "${@:3}"
}
