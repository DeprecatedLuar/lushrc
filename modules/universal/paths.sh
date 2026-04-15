#!/usr/bin/env bash
# PATH configurations

#==================== ENVIRONMENT VARIABLES ====================

#--[SHELL CONFIG ROOT]------------------------------------

# Single source of truth for shell config location
export BASHRC="$HOME/.config/lushrc"

#--[XDG DIRECTORIES]---------------------------------------

# Source and export XDG dirs (also symlinked to ~/.config/user-dirs.dirs for DE)
source "$BASHRC/modules/universal/xdg.sh"
export XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
export XDG_DESKTOP_DIR XDG_DOWNLOAD_DIR XDG_DOCUMENTS_DIR
export XDG_PICTURES_DIR XDG_VIDEOS_DIR XDG_MUSIC_DIR
export XDG_TEMPLATES_DIR XDG_PUBLICSHARE_DIR

#--[SYSTEM DIRECTORIES]------------------------------------

# GitHub user
export GITHUB_USER="DeprecatedLuar"

# Home-level standard directories
export BACKUP="$HOME/Backup"
export MEDIA="$HOME/Media"
export MEDIA_GALLERY="$MEDIA/gallery"
export PICTURES_GALLERY="$MEDIA_GALLERY/pictures"
export VIDEOS_GALLERY="$MEDIA_GALLERY/videos"
export AUDIO_GALLERY="$MEDIA_GALLERY/audio"
export WALLPAPERS_GALLERY="$MEDIA_GALLERY/wallpapers"
export DOCUMENTS="$HOME/Documents"
export GAMES="$HOME/Games"

# Downloads staging (ephemeral with rotation)
export DOWNLOADS_STAGE="${XDG_CACHE_HOME:-$HOME/.cache}/downloads"
export DOWNLOADS="$HOME/Downloads"

#--------------------- WORKSPACE VARS ----------------------

# Workspace root and main directories
export WORKSPACE="$HOME/Workspace"
export TOOLS="$WORKSPACE/tools"
export PROJECTS="$WORKSPACE/dev"
export SHARED="$WORKSPACE/shared"
export SATELLITE="$PROJECTS/cli/the-satellite"

# Tools subdirectories
export DOCKER_DIR="$WORKSPACE/docker"

# Script library directory
export LIBDIR="$BASHRC/bin/lib"

#------------------------ EXTRAS ---------------------------


export PIP_REQUIRE_VIRTUALENV=true

#==================== PATH CONFIGURATION ====================

#------------------- UNIVERSAL PATHS ----------------------

export PATH="$HOME/bin:$PATH"
export PATH="$BASHRC/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

#-------------------- DEV TOOLS PATHS ----------------------

# Add dev tools to PATH (environment variables set in .bashrc)
export PATH="$CARGO_HOME/bin:$PATH"           # Rust
export GOBIN="$HOME/.local/bin"               # Go binaries → unified user bin
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"    # npm

#==================== TERMINAL & RUNTIME ====================

# export TERM=xterm-256color  # Commented out - let terminal set its own TERM

# Fix terminfo for Nix packages (so they can find kitty's xterm-kitty terminfo)
export TERMINFO_DIRS="$HOME/.nix-profile/share/terminfo:/nix/var/nix/profiles/default/share/terminfo:/usr/share/terminfo${TERMINFO_DIRS:+:$TERMINFO_DIRS}"
