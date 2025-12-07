#!/usr/bin/env bash
# Bash configuration magazine

# Source paths first to get $BASHRC and other env vars
source "${BASHRC:-$HOME/.config/lushrc}/modules/universal/paths.sh"

# Ensure local configuration file exists
touch "$BASHRC/modules/local.sh"

# Source remaining module files (paths.sh already sourced xdg.sh)
source "$BASHRC/modules/defaults/defaults.sh"
source "$BASHRC/modules/universal/aliases.sh"
source "$BASHRC/modules/local.sh"

# Initialize zoxide (suppress write permission errors)
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# Override zoxide's z function with our enhanced wrapper
unset -f z 2>/dev/null
z() {
    . "$LIBDIR/z-wrapper.sh" "$@"
}

# Source bash completions
if [ -d "$TOOLS/bin/completions" ]; then
    for completion in "$TOOLS/bin/completions"/*; do
        [ -f "$completion" ] && source "$completion"
    done
fi

