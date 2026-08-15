#!/usr/bin/env bash
# needs: paths store (cronotrigger_job_names)
# Bash completion for `ctg`/`cronotrigger`. Sourced from an interactive shell only.

_cronotrigger_jobs() {
    local root="${CRONOTRIGGER_LUSHRC_ROOT:-${BASHRC:-$HOME/.config/lushrc}}"
    local lib="$root/bin/lib/cronotrigger"
    [[ -r "$lib/paths.sh" && -r "$lib/store.sh" ]] || return 0
    source "$lib/paths.sh"
    source "$lib/store.sh"
    cronotrigger_job_names 2>/dev/null
}

_cronotrigger() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if ((COMP_CWORD == 1)); then
        COMPREPLY=($(compgen -W "add a edit e list ls enable disable run remove rm help" -- "$cur"))
        return
    fi

    case "$prev" in
        edit|e|enable|disable|run|remove|rm)
            COMPREPLY=($(compgen -W "$(_cronotrigger_jobs)" -- "$cur"))
            ;;
    esac
}
complete -F _cronotrigger ctg cronotrigger
