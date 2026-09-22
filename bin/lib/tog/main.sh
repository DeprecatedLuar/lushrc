#!/usr/bin/env bash
# tog - alternate between two commands, or start/stop one
# Usage: tog [-n X|Y] CMD1 CMD2 | tog CMD | tog -p PROC CMD [CMD2]

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/tog"
EXIT_USAGE=2
NOTIFY_TITLE="tog"
NOTIFY_SEPS="|/" # either splits -n=X|Y; "/" needs no shell quoting
NOTIFY_DEFAULT="0|1"

die() { printf 'tog: %s\n' "$1" >&2; exit 1; }

usage() {
    echo "Usage: tog CMD1 CMD2        alternate CMD1, CMD2, CMD1, ...; prints 0 or 1" >&2
    echo "       tog -n CMD1 CMD2     same, and notify the state" >&2
    echo "       tog -n=X/Y CMD1 CMD2   same, and notify X after CMD1, Y after CMD2 ('|' also works, quoted)" >&2
    echo "       tog CMD              start CMD detached, or kill it if tog started it" >&2
    echo "       tog -p PROC CMD      kill PROC if running, else run CMD" >&2
    echo "       tog -p PROC CMD1 CMD2  CMD2 if PROC is running, else CMD1" >&2
    exit "$EXIT_USAGE"
}

is_running() {
    local rc=0
    pgrep -x -- "$1" >/dev/null || rc=$?
    case $rc in
        0) return 0 ;;
        1) return 1 ;;
        *) die "pgrep failed (exit $rc)" ;;
    esac
}

# state_path CMD... -> file keyed by the command strings
state_path() {
    local key
    key=$(printf '%s\n' "$@" | cksum | cut -d' ' -f1)
    printf '%s/%s\n' "$STATE_DIR" "$key"
}

# tracked_pid STATE -> prints the pid if that process is still alive
tracked_pid() {
    local pid
    [[ -r $1 ]] || return 1
    pid=$(<"$1")
    kill -0 -- "$pid" 2>/dev/null || return 1
    printf '%s\n' "$pid"
}

# The command leads its own session, so killing -PID takes down its whole tree.
# Its output goes to a log beside the pid file, not the terminal that pressed it.
launch_or_kill() {
    local cmd=$1 state pid
    state=$(state_path "$cmd")
    mkdir -p "$STATE_DIR"
    if pid=$(tracked_pid "$state"); then
        kill -- "-$pid"
        rm -f "$state" "$state.log"
    else
        setsid bash -c "$cmd" </dev/null >"$state.log" 2>&1 &
        printf '%s\n' "$!" >"$state"
    fi
}

# report_state N LABELS -> print N; notify the matching side of "x|y" if given
report_state() {
    local n=$1 labels=$2 label
    printf '%s\n' "$n"
    [[ -n $labels ]] || return 0
    if ((n == 0)); then label=${labels%%[$NOTIFY_SEPS]*}; else label=${labels#*[$NOTIFY_SEPS]}; fi
    notify-send -- "$NOTIFY_TITLE" "$label"
}

# State is flipped only after the command succeeds, so a failure retries it.
alternate() {
    local cmd1=$1 cmd2=$2 labels=$3 state
    state=$(state_path "$cmd1" "$cmd2")
    mkdir -p "$STATE_DIR"
    if [[ -e $state ]]; then
        bash -c "$cmd2"
        rm -f "$state"
        report_state 1 "$labels"
    else
        bash -c "$cmd1"
        touch "$state"
        report_state 0 "$labels"
    fi
}

by_process() {
    local proc=$1 start=$2 stop=${3:-}
    if ! is_running "$proc"; then
        bash -c "$start"
    elif [[ -n $stop ]]; then
        bash -c "$stop"
    else
        pkill -x -- "$proc"
    fi
}

main() {
    local proc="" notify="" cmds=()
    while (($#)); do
        case $1 in
            -p)           (($# >= 2)) || usage; proc=$2; shift 2 ;;
            -n|--notify)  notify=$NOTIFY_DEFAULT; shift ;;
            -n=*|--notify=*) notify=${1#*=}; shift ;;
            *)            cmds+=("$1"); shift ;;
        esac
    done
    (( ${#cmds[@]} == 1 || ${#cmds[@]} == 2 )) || usage
    set -- "${cmds[@]}"

    if [[ -n $notify ]]; then
        [[ -z $proc && $# -eq 2 ]] || die "-n only applies to the two-command form: tog -n CMD1 CMD2"
        [[ $notify == *[$NOTIFY_SEPS]* ]] || die "-n=X|Y needs two labels separated by one of '$NOTIFY_SEPS' (got '$notify')"
        command -v notify-send >/dev/null || die "notify-send not found"
    fi

    if [[ -n $proc ]]; then
        by_process "$proc" "$@"
    elif (($# == 1)); then
        launch_or_kill "$1"
    else
        alternate "$1" "$2" "$notify"
    fi
}

main "$@"
