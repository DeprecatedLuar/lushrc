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
    local cmd="${COMP_WORDS[0]}"
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    local subcommands="unlock ls list status key keys add a edit e remove rm mv rename get g tunnel t help"
    local lsh_flags="--password -P --no-tmux --no-mosh --raw --escape-hatch --help -h"
    local ssh_flags="-p -l -i -v -4 -6 -C -N -f -X -Y --password -P --no-tmux --no-mosh --raw --escape-hatch -h --help"
    local hosts="$(_lsh_names)"

    case "$prev" in
        -i)
            COMPREPLY=($(compgen -f -- "$cur"))
            return
            ;;
        -l)
            COMPREPLY=($(compgen -u -- "$cur"))
            return
            ;;
        -p|-P|--password)
            return
            ;;
    esac

    if [[ "$cur" == *@* ]]; then
        local user_prefix="${cur%%@*}@"
        local host_part="${cur#*@}"
        COMPREPLY=($(compgen -W "$hosts" -P "$user_prefix" -- "$host_part"))
        return
    fi

    if [[ "$cmd" == "lsh" ]]; then
        case "$prev" in
            edit|e|remove|rm|mv|rename|unlock|tunnel|t|get|g)
                COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
                return
                ;;
            key|keys)
                COMPREPLY=($(compgen -W "pub priv" -- "$cur"))
                return
                ;;
        esac

        COMPREPLY=($(compgen -W "$subcommands $hosts $lsh_flags" -- "$cur"))
    else
        # ssh
        COMPREPLY=($(compgen -W "$hosts $ssh_flags" -- "$cur"))
    fi
}
complete -F _lsh lsh ssh
