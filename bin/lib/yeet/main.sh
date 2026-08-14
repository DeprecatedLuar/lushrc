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
# Replacing a directory mirrors the source, so --delete must be scoped to the
# target item itself, never to the parent destination holding its siblings.
REPLACE_ARGS=(--delete)

PROMPT_COLLISION="[o]verwrite / [s]uffix / [N]o: "
PROMPT_MISMATCH="[s]uffix / [N]o: "

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
    echo "  -f, --force         Overwrite a colliding remote item without asking"
    echo "  -s, --suffix        Send under a suffixed name on collision, without asking"
    echo "  --debug             Enable debug output (path resolution)"
    echo "  -p PORT             SSH port (can also use host:port syntax)"
    echo "  -l USER             SSH user (can also use user@host syntax)"
    echo ""
    echo "Examples:"
    echo "  yeet file.txt nuremberg              # send to remote \$HOME"
    echo "  yeet backup.db .17:8022              # send to LAN host"
    echo "  yeet project/ vps d/backups          # nav-engine remote path"
    echo "  yeet --rm data.sql server w/data     # send and delete local source"
    echo "  yeet -f app/ server w/deploy         # replace existing remote app/"
    echo "  yeet -s app/ server w/deploy         # land beside it as app_/"
    echo "  yeet --debug data.db .17 ~/backups   # debug path resolution"
    exit 0
}

# --- Parse arguments ---
REMOVE_SOURCE=false
SKIP_CONFIRM=false
FORCE=false
SUFFIX=false
DEBUG=false
FLAG_USER=""
FLAG_PORT=""
POSITIONALS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)      show_help ;;
        --rm)           REMOVE_SOURCE=true; shift ;;
        -y|--yes)       SKIP_CONFIRM=true; shift ;;
        -f|--force)     FORCE=true; shift ;;
        -s|--suffix)    SUFFIX=true; shift ;;
        --debug)        DEBUG=true; shift ;;
        -p)             FLAG_PORT="$2"; shift 2 ;;
        -l)             FLAG_USER="$2"; shift 2 ;;
        -*)             die "unknown option: $1" ;;
        *)              POSITIONALS+=("$1"); shift ;;
    esac
done
set -- "${POSITIONALS[@]+"${POSITIONALS[@]}"}"

[[ $# -lt 2 ]] && show_help

[[ "$FORCE" == true && "$SUFFIX" == true ]] && die "-f and -s answer the same question differently; pick one"

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

# --- Collision handling ---
# A same-named remote item is replaced, not merged, so it needs consent of its
# own: -y covers the routine prompt, -f and -s each answer this one instead.
BASE_NAME="$(basename "$LOCAL_SOURCE")"
LANDS_AS="$BASE_NAME"
REPLACE=false
NEEDS_SUFFIX=false

if remote_exists "$DEST/$BASE_NAME"; then
    [[ -d "$LOCAL_SOURCE" ]] && LOCAL_TYPE=directory || LOCAL_TYPE=file
    remote_is_dir "$DEST/$BASE_NAME" && REMOTE_TYPE=directory || REMOTE_TYPE=file

    # rsync cannot swap a directory for a file or vice versa, so replacing is
    # off the table for a type mismatch: suffixing is the only way through
    if [[ "$LOCAL_TYPE" != "$REMOTE_TYPE" ]]; then
        [[ "$FORCE" == true ]] && die "cannot replace $REMOTE_TYPE $CONN_TARGET:$DEST/$BASE_NAME with a $LOCAL_TYPE; use -s to send it under another name"
        if [[ "$SUFFIX" == false ]]; then
            choice_block "$PROMPT_MISMATCH" "s" \
                "Yeeting"      "$C_PATH$LOCAL_SOURCE ($LOCAL_TYPE)" \
                "Blocked by"   "$C_WARN$CONN_TARGET:$DEST/$BASE_NAME ($REMOTE_TYPE)" \
                || { echo "Cancelled"; exit 0; }
        fi
        NEEDS_SUFFIX=true

    elif [[ "$FORCE" == true ]]; then
        REPLACE=true
    elif [[ "$SUFFIX" == true ]]; then
        NEEDS_SUFFIX=true
    else
        choice_block "$PROMPT_COLLISION" "os" \
            "Yeeting"       "$C_PATH$LOCAL_SOURCE" \
            "Already there" "$C_WARN$CONN_TARGET:$DEST/$BASE_NAME" \
            || { echo "Cancelled"; exit 0; }
        [[ "$CHOICE" == "o" ]] && REPLACE=true || NEEDS_SUFFIX=true
    fi

    if [[ "$NEEDS_SUFFIX" == true ]]; then
        LANDS_AS=$(remote_free_name "$DEST" "$BASE_NAME") \
            || die "no free name near $CONN_TARGET:$DEST/$BASE_NAME"
    fi

elif [[ "$SKIP_CONFIRM" == false ]]; then
    confirm_block \
        "Yeeting" "$C_PATH$LOCAL_SOURCE" \
        "To"      "$C_HOST$CONN_TARGET:$DEST" \
        || { echo "Cancelled"; exit 0; }
fi

FINAL_PATH="$DEST/$LANDS_AS"

# --- Transfer ---
if [[ "$REMOVE_SOURCE" == true ]]; then
    RSYNC_ARGS+=(--remove-source-files)
fi

# Addressing the landing path itself, rather than the destination it sits in,
# is what keeps --delete scoped to this item and what lets a suffix rename it
if [[ -d "$LOCAL_SOURCE" ]]; then
    SOURCE_ARG="$LOCAL_SOURCE/"
    TARGET_ARG="$CONN_TARGET:$FINAL_PATH/"
    [[ "$REPLACE" == true ]] && RSYNC_ARGS+=("${REPLACE_ARGS[@]}")
else
    SOURCE_ARG="$LOCAL_SOURCE"
    TARGET_ARG="$CONN_TARGET:$FINAL_PATH"
fi

conn_rsync "${RSYNC_ARGS[@]}" "$SOURCE_ARG" "$TARGET_ARG" \
    || die "transfer failed"

# --remove-source-files only unlinks files, leaving the directory skeleton
if [[ "$REMOVE_SOURCE" == true && -d "$LOCAL_SOURCE" ]]; then
    find "$LOCAL_SOURCE" -type d -empty -delete
fi

printf "Yeeted %s%s%s\n" "$C_PATH" "$LOCAL_SOURCE" "$C_RESET"
printf " %s→ %s:%s%s\n" "$C_HOST" "$CONN_TARGET" "$FINAL_PATH" "$C_RESET"
