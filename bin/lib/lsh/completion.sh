#!/usr/bin/env bash
# needs: list (lsh_list_entries)
# Bash completion for `lsh`/`ssh` (lsh shadow). Sourced from an interactive shell only.

_lsh_names() {
    local root="${LSH_LUSHRC_ROOT:-${BASHRC:-$HOME/.config/lushrc}}"
    local lib="$root/bin/lib/lsh"
    [[ -r "$lib/list.sh" ]] || return 0
    source "$lib/list.sh"
    lsh_list_entries 2>/dev/null | cut -f1
}

_lsh() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if ((COMP_CWORD == 1)); then
        COMPREPLY=($(compgen -W "unlock ls list status key keys add a edit e remove rm mv rename tunnel t help" -- "$cur"))
        return
    fi

    case "$prev" in
        edit|e|remove|rm|mv|rename|unlock|tunnel|t)
            COMPREPLY=($(compgen -W "$(_lsh_names)" -- "$cur"))
            ;;
    esac
}
complete -F _lsh lsh ssh
