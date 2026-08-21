#!/usr/bin/env bash
# Bash completion for `lushrun`. Sourced from an interactive shell only.

_lushrun() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "$prev" == "lushrun" ]]; then
        COMPREPLY=($(compgen -f -- "$cur"; compgen -A command -- "$cur"))
    fi
}
complete -F _lushrun lushrun
