#!/usr/bin/env bash
# prompt.sh — interactive confirmation blocks
#
#     confirm_block <heading> <value> [<heading> <value> ...]
#     choice_block <prompt> <letters> <heading> <value> [...]
#
# Both print heading/value pairs, prompt, then erase the whole block so the
# caller can print its own result in the reclaimed space.
# confirm_block is Y/n and returns 1 if declined. choice_block accepts only the
# letters in <letters>, leaves the picked one in $CHOICE, and returns 1 for
# anything else, so a bare Enter always declines a destructive question.
# Values are printed as given: colorize with the constants below so callers own
# the semantics and this owns the layout.

C_PATH=$'\033[34m'
C_HOST=$'\033[1;36m'
C_WARN=$'\033[1;33m'
C_RESET=$'\033[0m'

LINES_PER_PAIR=2
LINES_TRAILING=2   # blank separator + the prompt line itself

PROMPT_DEFAULT_YES="Y/n: "

CHOICE=""
BLOCK_LINES=0

# Prints the pairs; leaves the line count it consumed in $BLOCK_LINES
print_block() {
    BLOCK_LINES=$LINES_TRAILING

    while [[ $# -ge 2 ]]; do
        printf '%s:\n  %s%s\n' "$1" "$2" "$C_RESET"
        BLOCK_LINES=$((BLOCK_LINES + LINES_PER_PAIR))
        shift 2
    done
    printf '\n'
}

erase_block() {
    printf '\033[%dA\033[J' "$1"
}

confirm_block() {
    local reply
    print_block "$@"
    local lines=$BLOCK_LINES

    read -rp "$PROMPT_DEFAULT_YES" reply
    [[ "$reply" =~ ^[Nn] ]] && return 1

    erase_block "$lines"
    return 0
}

choice_block() {
    local prompt="$1" letters="$2"
    shift 2

    local reply
    print_block "$@"
    local lines=$BLOCK_LINES

    read -rp "$prompt" reply
    CHOICE="${reply:0:1}"
    CHOICE="${CHOICE,,}"
    [[ -n "$CHOICE" && "$letters" == *"$CHOICE"* ]] || { CHOICE=""; return 1; }

    erase_block "$lines"
    return 0
}
