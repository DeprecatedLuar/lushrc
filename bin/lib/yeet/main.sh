#!/usr/bin/env bash
# yeet - send files to remote machines
# shared: net.sh ssh-conn.sh
# needs: yeetyoink

set -euo pipefail

LIBDIR="${LIBDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SYSDIR="${SYSDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../system" && pwd)}"
source "$SYSDIR/shared/net.sh"
source "$SYSDIR/shared/ssh-conn.sh"
source "$LIBDIR/yeetyoink/remote.sh"
source "$LIBDIR/yeetyoink/prompt.sh"

DEFAULT_REMOTE_DEST="~"
RSYNC_ARGS=(-az --info=progress2 --no-inc-recursive)

die() { printf 'yeet: %s\n' "$1" >&2; exit 1; }

show_help() {
    echo "Usage: yeet [OPTIONS] local_source [user@]host[:port] [remote_path]"
    echo ""
    echo "Send files to remote machines using rsync over SSH."
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  --rm                Remove source files after transfer"
    echo "  -y, --yes           Skip confirmation prompt"
    echo "  --debug             Enable debug output (path resolution)"
    echo "  -p PORT             SSH port (can also use host:port syntax)"
    echo "  -l USER             SSH user (can also use user@host syntax)"
    echo ""
    echo "Examples:"
    echo "  yeet file.txt nuremberg              # send to remote \$HOME"
    echo "  yeet backup.db .17:8022              # send to LAN host"
    echo "  yeet project/ vps d/backups          # nav-engine remote path"
    echo "  yeet --rm data.sql server w/data     # send and delete local source"
    echo "  yeet --debug data.db .17 ~/backups   # debug path resolution"
    exit 0
}

# --- Parse arguments ---
REMOVE_SOURCE=false
SKIP_CONFIRM=false
DEBUG=false
FLAG_USER=""
FLAG_PORT=""
POSITIONALS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)      show_help ;;
        --rm)           REMOVE_SOURCE=true; shift ;;
        -y|--yes)       SKIP_CONFIRM=true; shift ;;
        --debug)        DEBUG=true; shift ;;
        -p)             FLAG_PORT="$2"; shift 2 ;;
        -l)             FLAG_USER="$2"; shift 2 ;;
        -*)             die "unknown option: $1" ;;
        *)              POSITIONALS+=("$1"); shift ;;
    esac
done
set -- "${POSITIONALS[@]+"${POSITIONALS[@]}"}"

[[ $# -lt 2 ]] && show_help

LOCAL_SOURCE="${1%/}"
parse_conn "$2" "$FLAG_USER" "$FLAG_PORT" || exit 1

# Local home references are rewritten to tilde so the remote resolves its own
DEST_QUERY="${3:-$DEFAULT_REMOTE_DEST}"
DEST_QUERY="${DEST_QUERY/#$HOME/\~}"

[[ -e "$LOCAL_SOURCE" ]] || die "source not found: $LOCAL_SOURCE"

# --- Resolve remote destination ---
if [[ "$DEBUG" == true ]]; then
    DEST=$(remote_resolve_path "$DEST_QUERY" "--debug") \
        || die "failed to resolve '$DEST_QUERY' on $CONN_TARGET"
else
    DEST=$(remote_resolve_path "$DEST_QUERY" "" 2>/dev/null) \
        || die "failed to resolve '$DEST_QUERY' on $CONN_TARGET"
fi

remote_has rsync || die "rsync not found on $CONN_TARGET"

if [[ "$SKIP_CONFIRM" == false ]]; then
    confirm_block \
        "Yeeting" "$C_PATH$LOCAL_SOURCE" \
        "To"      "$C_HOST$CONN_TARGET:$DEST" \
        || { echo "Cancelled"; exit 0; }
fi

# --- Transfer ---
if [[ "$REMOVE_SOURCE" == true ]]; then
    RSYNC_ARGS+=(--remove-source-files)
fi

conn_rsync "${RSYNC_ARGS[@]}" "$LOCAL_SOURCE" "$CONN_TARGET:$DEST/" \
    || die "transfer failed"

# --remove-source-files only unlinks files, leaving the directory skeleton
if [[ "$REMOVE_SOURCE" == true && -d "$LOCAL_SOURCE" ]]; then
    find "$LOCAL_SOURCE" -type d -empty -delete
fi

printf "Yeeted %s%s%s\n" "$C_PATH" "$LOCAL_SOURCE" "$C_RESET"
printf " %s→ %s:%s%s\n" "$C_HOST" "$CONN_TARGET" "$DEST" "$C_RESET"
