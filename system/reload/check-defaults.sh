#!/usr/bin/env bash
# Warn about program defaults naming something this machine does not have.
#
# $LUSHRC_DEFAULTS is hand-edited and outside the repo, so nothing else would
# catch it drifting from what is installed. Silent when every role resolves;
# one stderr line per role that does not. Never fails reload.

DEFAULT_ROLES="TERMINAL EDITOR VISUAL BROWSER DATA_VIEWER MEDIA_PLAYER AUDIO_PLAYER IMAGE_VIEWER FILEMANAGER LAUNCHER"

main() {
    local defaults="${LUSHRC_DEFAULTS:-${XDG_DATA_HOME:-$HOME/.local/share}/lushrc/defaults.sh}"
    [[ -f $defaults ]] || return 0

    local role value binary

    # reload runs from a shell that already exports these, so clear them first:
    # otherwise a role deleted from the file still resolves from the inherited
    # environment and warns forever.
    for role in $DEFAULT_ROLES; do
        unset "$role"
    done

    # shellcheck source=/dev/null
    source "$defaults" 2>/dev/null || return 0

    for role in $DEFAULT_ROLES; do
        value="${!role:-}"
        [[ -z $value ]] && continue

        # A value may be a full command line (LAUNCHER), so only the first
        # word is a binary to look for.
        binary="${value%% *}"

        type -P "$binary" >/dev/null 2>&1 && continue
        printf 'defaults: %s=%s not found in PATH\n' "$role" "$binary" >&2
    done

    return 0
}

main
