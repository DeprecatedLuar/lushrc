#!/usr/bin/env bash
# needs: paths systemd (bigbrother_defined_names / bigbrother_transient_names)
# Bash completion for `bb`/`bigbrother`. Sourced from an interactive shell only.

_bigbrother_services() {
    local root="${BIGBROTHER_LUSHRC_ROOT:-${BASHRC:-$HOME/.config/lushrc}}"
    local lib="$root/bin/lib/bigbrother"
    [[ -r "$lib/paths.sh" && -r "$lib/systemd.sh" ]] || return 0
    source "$lib/paths.sh"
    source "$lib/systemd.sh"
    bigbrother_defined_names 2>/dev/null
    bigbrother_transient_names 2>/dev/null
}

_bigbrother() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if ((COMP_CWORD == 1)); then
        COMPREPLY=($(compgen -W "ls list add a rm remove mv rename enable up disable down run stop restart logs watch tail attach edit e help" -- "$cur"))
        return
    fi

    # `run` and `add` take a command line, so past their flags there is nothing
    # service-shaped left to complete — hand those words to command completion.
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-n -c --name --command --workdir" -- "$cur"))
        return
    fi

    case "$prev" in
        -c|--command)
            COMPREPLY=($(compgen -c -- "$cur"))
            ;;
        --workdir)
            COMPREPLY=($(compgen -d -- "$cur"))
            ;;
        -n|--name)
            ;;
        edit|e|rm|remove|mv|rename|enable|up|disable|down|run|stop|restart|logs|watch|tail|attach)
            COMPREPLY=($(compgen -W "$(_bigbrother_services)" -- "$cur"))
            ;;
    esac
}
complete -F _bigbrother bb bigbrother
