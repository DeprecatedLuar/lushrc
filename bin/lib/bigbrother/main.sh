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

    # Bare-path shortcut: `bb ./binary` or `bb /abs/binary` routes to `run`.
    if [[ "$command" == */* ]] || { [[ -f "$command" ]] && [[ -x "$command" ]]; }; then
        bigbrother_init_paths
        bigbrother_cmd_run "$command" "$@"
        return
    fi

    bigbrother_init_paths

    case "$command" in
        ls|list)          (($# == 0)) || { echo "Usage: bigbrother ls" >&2; return 1; }; bigbrother_cmd_ls ;;
        add)               bigbrother_cmd_add "$@" ;;
        rm|remove)         bigbrother_cmd_rm "$@" ;;
        enable|up)         bigbrother_cmd_enable "$@" ;;
        disable|down)      bigbrother_cmd_disable "$@" ;;
        run)               bigbrother_cmd_run "$@" ;;
        stop)              bigbrother_cmd_stop "$@" ;;
        restart)           bigbrother_cmd_restart "$@" ;;
        logs)              bigbrother_cmd_logs "$@" ;;
        edit)              bigbrother_cmd_edit "$@" ;;
        help|-h|--help)    (($# == 0)) || { echo "Usage: bigbrother help" >&2; return 1; }; bigbrother_cmd_help ;;
        *)
            echo "bigbrother: unknown command '$command'" >&2
            bigbrother_cmd_help >&2
            return 1
            ;;
    esac
}

bigbrother_main "$@"
