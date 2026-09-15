#!/usr/bin/env bash
# Seed a machine-local defaults file. Runs once, when the target is absent.
#
# The repo ships no defaults.sh: a committed file would assert programs the
# machine may not have. This generates one from what is actually installed,
# then never touches it again — the result belongs to the machine, not to git.

set -euo pipefail

DEFAULTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lushrc"
DEFAULTS_FILE="$DEFAULTS_DIR/defaults.sh"

# Resolved roles: must land on something real or common tooling breaks.
TERMINAL_CANDIDATES="kitty ghostty foot alacritty wezterm konsole gnome-terminal xfce4-terminal urxvt st xterm"
EDITOR_CANDIDATES="micro nvim vim vi nano"

# Declared-but-empty roles: no sane machine-independent default exists.
PLACEHOLDER_ROLES="BROWSER DATA_VIEWER MEDIA_PLAYER AUDIO_PLAYER IMAGE_VIEWER FILEMANAGER LAUNCHER"

# pick VAR cmd... — first candidate present in PATH wins; VAR left empty if none.
# type -P, not command -v: only real binaries count, never functions or aliases.
pick() {
    local var=$1 c
    shift
    for c in "$@"; do
        if type -P "$c" >/dev/null 2>&1; then
            printf -v "$var" '%s' "$c"
            return 0
        fi
    done
    printf -v "$var" '%s' ''
}

emit() {
    local terminal=$1 editor=$2 role

    printf '#!/usr/bin/env bash\n'
    printf '# Default program configurations — seeded from what this machine had installed.\n\n'

    printf 'export TERMINAL="%s"\n\n' "$terminal"
    printf 'export EDITOR="%s"\n' "$editor"
    printf 'export VISUAL="%s"\n\n' "$editor"

    printf '# Unresolved on this machine — uncomment and fill in as you install them:\n'
    for role in $PLACEHOLDER_ROLES; do
        printf '#export %s=""\n' "$role"
    done
}

main() {
    if [[ -e $DEFAULTS_FILE && ${1:-} != --force ]]; then
        printf 'gen-defaults: %s already exists (use --force to replace)\n' "$DEFAULTS_FILE" >&2
        return 1
    fi

    mkdir -p "$DEFAULTS_DIR"

    local terminal editor
    pick terminal $TERMINAL_CANDIDATES
    pick editor $EDITOR_CANDIDATES

    emit "$terminal" "$editor" >"$DEFAULTS_FILE"
}

main "$@"
