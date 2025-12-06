#!/usr/bin/env bash
# Ensure directory structure exists
# Creates all directories declared in paths.sh

# Source paths if not already loaded
if [ -z "$BASHRC" ]; then
    source "${BASHRC:-$HOME/.config/lushrc}/modules/universal/paths.sh"
fi

#--[HOME-LEVEL DIRECTORIES]---------------------

mkdir -p "$BACKUP"
mkdir -p "$MEDIA"
mkdir -p "$DOCUMENTS"
mkdir -p "$DOWNLOADS"
mkdir -p "$DOWNLOADS_STAGE/previous"
mkdir -p "$HOME/bin"
mkdir -p "$HOME/bin/lib"
mkdir -p "$HOME/bin/sys"

#--[MEDIA SUBDIRECTORIES]-----------------------

mkdir -p "$AUDIO"
mkdir -p "$PICTURES"
mkdir -p "$VIDEOS"

#--[WORKSPACE STRUCTURE]------------------------

mkdir -p "$WORKSPACE"
mkdir -p "$TOOLS"
mkdir -p "$PROJECTS"
mkdir -p "$SHARED"

# Workspace tools subdirectories
mkdir -p "$TOOLS_FOREIGN"
mkdir -p "$HOMEMADE"
mkdir -p "$DOCKER_DIR"
mkdir -p "$TOOLS/bin"
mkdir -p "$TOOLS/bin/lib"
mkdir -p "$TOOLS/bin/completions"

#--[CRITICAL SHELL SYMLINKS]-------------------

# Ensure shell config symlinks exist
ln -sf "$BASHRC/bashrc" "$HOME/.bashrc" 2>/dev/null || true
ln -sf "$BASHRC/profile" "$HOME/.profile" 2>/dev/null || true

#--[CONVENIENCE SYMLINKS]-----------------------

# Create symlinks for easier access to hidden directories
ln -sf .local "$HOME/Local" 2>/dev/null || true
ln -sf .config "$HOME/Config" 2>/dev/null || true

#--[VERIFICATION]-------------------------------

if [[ "$1" == "-v" ]] || [[ "$1" == "--verbose" ]]; then
    echo "✓ Directory structure verified:"
    echo "  Home: bin, Backup, Media, Documents, Downloads"
    echo "  Downloads cache: $DOWNLOADS_STAGE/previous"
    echo "  Media: Audio, Pictures, Videos"
    echo "  Workspace: projects, shared, tools"
    echo "  Tools: foreign, homemade, docker, bin"
    echo "  Shell: ~/.bashrc → $BASHRC/bashrc"
    echo "  Shell: ~/.profile → $BASHRC/profile"
    echo "  Convenience: ~/Local → .local, ~/Config → .config"
fi
