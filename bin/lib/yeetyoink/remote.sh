#!/usr/bin/env bash
# remote.sh — queries against the host held by ssh-conn.sh
#
#     remote_resolve_path <query> [nav_flags]  → absolute remote path on stdout
#     remote_has <command>                     → 0 if the command exists remotely
#     remote_exists <path>                     → 0 if the path exists remotely
#     remote_is_dir <path>                     → 0 if the path is a directory remotely
#     remote_free_name <dir> <name>            → first unused name under <dir> on stdout
#
# Path resolution ships nav-engine.sh over stdin, so the remote host needs
# nothing installed beyond bash.
#
# Requires: shared/ssh-conn.sh (conn_ssh), $SYSDIR

NAV_ENGINE="$SYSDIR/shared/nav-engine.sh"

SUFFIX_CHAR="_"
SUFFIX_MAX_TRIES=10

remote_resolve_path() {
    local query="$1" nav_flags="${2:-}"
    conn_ssh_pipe "TERM=dumb bash -s -- $nav_flags '$query'" < "$NAV_ENGINE"
}

remote_has() {
    conn_ssh "command -v '$1' >/dev/null 2>&1"
}

remote_exists() {
    conn_ssh "test -e '$1'" 2>/dev/null
}

remote_is_dir() {
    conn_ssh "test -d '$1'" 2>/dev/null
}

remote_free_name() {
    local dir="$1" name="$2" i

    for ((i = 0; i < SUFFIX_MAX_TRIES; i++)); do
        name="${name}${SUFFIX_CHAR}"
        remote_exists "$dir/$name" || { printf '%s' "$name"; return 0; }
    done

    return 1
}
