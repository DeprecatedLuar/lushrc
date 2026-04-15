#!/usr/bin/env bash
# Downloads rotation - keeps ~/Downloads clean with one backup cycle
# Runs on login: if newest download is >24h old, move contents to cache

# Source paths if not loaded
if [ -z "$DOWNLOADS_STAGE" ]; then
    source "${BASHRC:-$HOME/.config/lushrc}/modules/universal/paths.sh"
fi

PREVIOUS="$DOWNLOADS_STAGE/previous"
MAX_AGE_MINUTES=1440  # 24 hours

mkdir -p "$DOWNLOADS" "$PREVIOUS"
ln -sfn "$PREVIOUS" "$DOWNLOADS/.previous"

# Skip if Downloads is empty
[ -z "$(ls -A "$DOWNLOADS" 2>/dev/null)" ] && return 0

# Check if newest file is older than 24h
newest=$(find "$DOWNLOADS" -maxdepth 1 -type f -mmin -$MAX_AGE_MINUTES -print -quit 2>/dev/null)

# If no recent files, rotate
if [ -z "$newest" ]; then
    rm -rf "$PREVIOUS"
    mkdir -p "$PREVIOUS"
    mv "$DOWNLOADS"/* "$PREVIOUS"/ 2>/dev/null
fi
