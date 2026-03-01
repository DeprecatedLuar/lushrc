#!/usr/bin/env bash
# sync-mime-defaults.sh
# Syncs MIME type defaults from defaults.sh variables to mimeapps.list

set -eo pipefail

# Source defaults to get variables
source "$BASHRC/modules/defaults/defaults.sh"

MIMEAPPS="$BASHRC/modules/defaults/mimeapps.list"

#--[FIND DESKTOP FILES]---------------------------

find_desktop_file() {
    local program="$1"
    [[ -z "$program" ]] && return 1

    local search_paths=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
        "/usr/local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
    )

    # Try exact match first
    for path in "${search_paths[@]}"; do
        [[ -f "$path/$program.desktop" ]] && echo "$program.desktop" && return 0
    done

    # Try case-insensitive fuzzy search
    for path in "${search_paths[@]}"; do
        local found=$(find "$path" -maxdepth 1 -iname "*$program*.desktop" 2>/dev/null | head -n1)
        [[ -n "$found" ]] && basename "$found" && return 0
    done

    # Fallback
    echo "$program.desktop"
}

IMAGE_VIEWER_DESKTOP=$(find_desktop_file "$IMAGE_VIEWER")
MEDIA_PLAYER_DESKTOP=$(find_desktop_file "$MEDIA_PLAYER")
BROWSER_DESKTOP=$(find_desktop_file "$BROWSER")

#--[UPDATE MIME ASSOCIATIONS]---------------------

# Create a temp file for the new mimeapps.list
TEMP_MIME=$(mktemp)

# Track if we're in the [Default Applications] section
in_default_section=false

# MIME type mappings
declare -A mime_map=(
    # Images
    ["image/png"]="$IMAGE_VIEWER_DESKTOP"
    ["image/jpeg"]="$IMAGE_VIEWER_DESKTOP"
    ["image/jpg"]="$IMAGE_VIEWER_DESKTOP"
    ["image/gif"]="$IMAGE_VIEWER_DESKTOP"
    ["image/webp"]="$IMAGE_VIEWER_DESKTOP"
    ["image/bmp"]="$IMAGE_VIEWER_DESKTOP"
    ["image/svg+xml"]="$IMAGE_VIEWER_DESKTOP"
    ["image/tiff"]="$IMAGE_VIEWER_DESKTOP"

    # Videos (common formats)
    ["video/mp4"]="$MEDIA_PLAYER_DESKTOP"
    ["video/x-matroska"]="$MEDIA_PLAYER_DESKTOP"
    ["video/webm"]="$MEDIA_PLAYER_DESKTOP"
    ["video/quicktime"]="$MEDIA_PLAYER_DESKTOP"
    ["video/x-msvideo"]="$MEDIA_PLAYER_DESKTOP"
    ["video/mpeg"]="$MEDIA_PLAYER_DESKTOP"

    # Audio (common formats)
    ["audio/mpeg"]="$MEDIA_PLAYER_DESKTOP"
    ["audio/mp3"]="$MEDIA_PLAYER_DESKTOP"
    ["audio/ogg"]="$MEDIA_PLAYER_DESKTOP"
    ["audio/flac"]="$MEDIA_PLAYER_DESKTOP"
    ["audio/wav"]="$MEDIA_PLAYER_DESKTOP"
    ["audio/x-wav"]="$MEDIA_PLAYER_DESKTOP"

    # Web
    ["text/html"]="$BROWSER_DESKTOP"
    ["x-scheme-handler/http"]="$BROWSER_DESKTOP"
    ["x-scheme-handler/https"]="$BROWSER_DESKTOP"
    ["x-scheme-handler/chrome"]="$BROWSER_DESKTOP"
    ["application/xhtml+xml"]="$BROWSER_DESKTOP"
)

# Read the existing mimeapps.list and update
while IFS= read -r line; do
    # Detect section headers
    if [[ "$line" == "[Default Applications]" ]]; then
        in_default_section=true
        echo "$line" >> "$TEMP_MIME"
        continue
    elif [[ "$line" =~ ^\[.*\]$ ]]; then
        in_default_section=false
        echo "$line" >> "$TEMP_MIME"
        continue
    fi

    # If we're in [Default Applications], check if we need to update this line
    if $in_default_section && [[ "$line" =~ ^([^=]+)= ]]; then
        mime_type="${BASH_REMATCH[1]}"
        if [[ -n "${mime_map[$mime_type]}" ]]; then
            # Replace with our mapping
            echo "$mime_type=${mime_map[$mime_type]}" >> "$TEMP_MIME"
            # Mark as processed
            unset mime_map["$mime_type"]
        else
            # Keep original line
            echo "$line" >> "$TEMP_MIME"
        fi
    else
        # Outside [Default Applications] or not a key=value line
        echo "$line" >> "$TEMP_MIME"
    fi
done < "$MIMEAPPS"

# Append any remaining unmapped types to [Default Applications]
if [[ ${#mime_map[@]} -gt 0 ]]; then
    for mime_type in "${!mime_map[@]}"; do
        echo "$mime_type=${mime_map[$mime_type]}" >> "$TEMP_MIME"
    done
fi

# Replace original file
mv "$TEMP_MIME" "$MIMEAPPS"

echo "✓ MIME defaults synced from defaults.sh"
