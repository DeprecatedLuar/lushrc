#!/usr/bin/env bash
# remote.sh — queries against the host held by ssh-conn.sh
#
#     remote_resolve_path <query> [nav_flags]  → absolute remote path on stdout
#     remote_has <command>                     → 0 if the command exists remotely
#     remote_exists <path>                     → 0 if the path exists remotely
#
# Path resolution ships nav-engine.sh over stdin, so the remote host needs
# nothing installed beyond bash.
#
# Requires: shared/ssh-conn.sh (conn_ssh), $LIBDIR

NAV_ENGINE="$LIBDIR/shared/nav-engine.sh"

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
