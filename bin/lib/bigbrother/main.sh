#!/usr/bin/env bash

set -euo pipefail

BIGBROTHER_LUSHRC_ROOT="${BIGBROTHER_LUSHRC_ROOT:-${BASHRC:-$HOME/.config/lushrc}}"
BIGBROTHER_LIBRARY_DIR="$BIGBROTHER_LUSHRC_ROOT/bin/lib/bigbrother"

for module in paths systemd unit commands; do
    module_path="$BIGBROTHER_LIBRARY_DIR/$module.sh"
    [[ -r "$module_path" ]] || {
        echo "bigbrother: missing module $module_path" >&2
        exit 1
    }
    # shellcheck source=/dev/null
    source "$module_path"
done
unset module module_path

bigbrother_main() {
    local command="${1:-ls}"
    (($# > 0)) && shift

    case "$command" in
        help|-h|--help) ;;
        *) bigbrother_require_systemd || exit 1 ;;
    esac

    bigbrother_init_paths

    case "$command" in
        ls|list)          (($# == 0)) || { echo "Usage: bigbrother ls" >&2; return 1; }; bigbrother_cmd_ls ;;
        get|g)             bigbrother_cmd_get "$@" ;;
        add|a)             bigbrother_cmd_add "$@" ;;
        rm|remove)         bigbrother_cmd_rm "$@" ;;
        mv|rename)         bigbrother_cmd_mv "$@" ;;
        enable|up)         bigbrother_cmd_enable "$@" ;;
        disable|down)      bigbrother_cmd_disable "$@" ;;
        run)               bigbrother_cmd_run "$@" ;;
        stop)              bigbrother_cmd_stop "$@" ;;
        restart)           bigbrother_cmd_restart "$@" ;;
        logs)              bigbrother_cmd_logs "$@" ;;
        watch|tail|attach) bigbrother_cmd_watch "$@" ;;
        edit|e)            bigbrother_cmd_edit "$@" ;;
        help|-h|--help)    (($# == 0)) || { echo "Usage: bigbrother help" >&2; return 1; }; bigbrother_cmd_help ;;
        *)
            # Bare known service name drops into the live view: `bb mentoros-api_`.
            if bigbrother_is_defined "$command" || bigbrother_is_transient "$command" 2>/dev/null; then
                bigbrother_cmd_watch "$command" "$@"
                return
            fi
            echo "bigbrother: unknown command '$command'" >&2
            bigbrother_cmd_help >&2
            return 1
            ;;
    esac
}

bigbrother_main "$@"
