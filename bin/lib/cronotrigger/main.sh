#!/usr/bin/env bash

set -euo pipefail

CRONOTRIGGER_LUSHRC_ROOT="${CRONOTRIGGER_LUSHRC_ROOT:-${BASHRC:-$HOME/.config/lushrc}}"
CRONOTRIGGER_LIBRARY_DIR="$CRONOTRIGGER_LUSHRC_ROOT/bin/lib/cronotrigger"
CRONOTRIGGER_BIN="${CRONOTRIGGER_BIN:-$CRONOTRIGGER_LUSHRC_ROOT/bin/cronotrigger}"
CRONOTRIGGER_BASH_BIN="${CRONOTRIGGER_BASH_BIN:-$(command -v bash)}"
CRONOTRIGGER_EXEC_PATH="${CRONOTRIGGER_EXEC_PATH:-$PATH}"
CRONOTRIGGER_INTERRUPT_STATUS=130
CRONOTRIGGER_TERMINATE_STATUS=143

for module in paths store schedule backend runner commands; do
    module_path="$CRONOTRIGGER_LIBRARY_DIR/$module.sh"
    [[ -r "$module_path" ]] || {
        echo "cronotrigger: missing module $module_path" >&2
        exit 1
    }
    # shellcheck source=/dev/null
    source "$module_path"
done
unset module module_path

cronotrigger_main() {
    local command="${1:-help}"
    (($# > 0)) && shift

    cronotrigger_init_paths

    if [[ "$command" == _run ]]; then
        [[ $# -eq 1 ]] || { echo "cronotrigger: internal runner requires one job name" >&2; return 1; }
        cronotrigger_run_job "$1" scheduled
        return
    fi

    cronotrigger_acquire_lock
    trap cronotrigger_release_lock EXIT
    trap 'exit "$CRONOTRIGGER_INTERRUPT_STATUS"' INT
    trap 'exit "$CRONOTRIGGER_TERMINATE_STATUS"' TERM
    cronotrigger_self_heal

    case "$command" in
        add|a) cronotrigger_cmd_add "$@" ;;
        edit|e) cronotrigger_cmd_edit "$@" ;;
        list|ls) (($# == 0)) || { echo "Usage: cronotrigger list" >&2; return 1; }; cronotrigger_cmd_list ;;
        get|g) cronotrigger_cmd_get "$@" ;;
        enable) cronotrigger_cmd_set_enabled "$@" true ;;
        disable) cronotrigger_cmd_set_enabled "$@" false ;;
        run) cronotrigger_cmd_run "$@" ;;
        remove|rm) cronotrigger_cmd_remove "$@" ;;
        help|-h|--help) (($# == 0)) || { echo "Usage: cronotrigger help" >&2; return 1; }; cronotrigger_cmd_help ;;
        *)
            echo "cronotrigger: unknown command '$command'" >&2
            cronotrigger_cmd_help >&2
            return 1
            ;;
    esac
}

cronotrigger_main "$@"
