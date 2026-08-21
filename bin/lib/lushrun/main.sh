#!/usr/bin/env bash
# Run an AppImage on NixOS via steam-run's FHS sandbox + appimage-run,
# with common Electron libs (missing from steam-run's sandbox) resolved
# dynamically so this doesn't rot when the nix store is GC'd.
set -euo pipefail

REQUIRED_DEPS=(steam-run appimage-run nix)
EXTRA_LIBS=(libxshmfence)

usage() {
    echo "Usage: lushrun <file.AppImage> [args...]" >&2
    exit 1
}

check_deps() {
    for dep in "${REQUIRED_DEPS[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || {
            echo "lushrun: required command '$dep' not found in PATH" >&2
            exit 1
        }
    done
}

resolve_lib_path() {
    local lib_path=""
    local pkg out
    for pkg in "${EXTRA_LIBS[@]}"; do
        out=$(nix build "nixpkgs#${pkg}" --no-link --print-out-paths)
        lib_path="${lib_path:+$lib_path:}${out}/lib"
    done
    echo "$lib_path"
}

main() {
    [ $# -lt 1 ] && usage
    check_deps

    local appimage
    appimage=$(realpath -e "$1" 2>/dev/null) \
        || appimage=$(command -v -- "$1" 2>/dev/null) \
        || {
            echo "lushrun: file not found: $1" >&2
            exit 1
        }
    shift

    local lib_path
    lib_path=$(resolve_lib_path)

    exec steam-run env LD_LIBRARY_PATH="${lib_path}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        appimage-run "$appimage" "$@"
}

main "$@"
