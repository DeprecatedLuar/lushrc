#!/usr/bin/env bash

#--[ENSURE DIRECTORY STRUCTURE]-----------------

source "$LIBDIR/ensure-dirs.sh"

#--[MAKE SCRIPTS EXECUTABLE]-------------------

chmod +x $TOOLS/bin/* 2>/dev/null || true
chmod +x $TOOLS/bin/lib/* 2>/dev/null || true
chmod +x $BASHRC/bin/* 2>/dev/null || true
chmod +x $LIBDIR/* 2>/dev/null || true
chmod +x $HOME/bin/* 2>/dev/null || true
chmod +x $HOME/bin/sys/* 2>/dev/null || true

#--[SYNC SYMLINKS]-----------------------------

source "$LIBDIR/symlink-farm.sh"
ln -sf "$BASHRC/modules/defaults/mimeapps.list" "$HOME/.config/mimeapps.list"

#--[SYSTEM-LEVEL SYNC]-------------------------

if [[ "$1" == "--system" ]] || [[ "$1" == "-s" ]] || [[ "$1" == "--hard" ]] || [[ "$1" == "-h" ]]; then
    sync_system_links
fi

#--[ENSURE KITTY TERMINFO]---------------------

if ! infocmp xterm-kitty &>/dev/null; then
    if ! sat install kitty-terminfo:sys 2>/dev/null; then
        export TERM=xterm-256color
    fi
fi

#--[REFRESH COMMAND HASH]-----------------------

hash -r
