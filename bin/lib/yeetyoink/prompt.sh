#!/usr/bin/env bash
# prompt.sh — interactive confirmation blocks
#
#     confirm_block <heading> <value> [<heading> <value> ...]
#
# Prints heading/value pairs, prompts Y/n, then erases the whole block so the
# caller can print its own result in the reclaimed space.
# Returns 1 if declined. Values are printed as given — colorize with the
# constants below so callers own the semantics and this owns the layout.

C_PATH=$'\033[34m'
C_HOST=$'\033[1;36m'
C_RESET=$'\033[0m'

LINES_PER_PAIR=2
LINES_TRAILING=2   # blank separator + the prompt line itself

confirm_block() {
    local lines=$LINES_TRAILING

    while [[ $# -ge 2 ]]; do
        printf '%s:\n  %s%s\n' "$1" "$2" "$C_RESET"
        lines=$((lines + LINES_PER_PAIR))
        shift 2
    done
    printf '\n'

    local reply
    read -rp "Y/n: " reply
    [[ "$reply" =~ ^[Nn] ]] && return 1

    printf '\033[%dA\033[J' "$lines"
    return 0
}
