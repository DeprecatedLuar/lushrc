#!/usr/bin/env bash

# Self-healing symlink structure
# Source once - ensures entire symlink farm is correct
# Skips gracefully if directories don't exist

#--[CLEANUP]------------------------------------

cleanup_broken_links() {
    local dirs=("$HOME/bin" "$HOME/bin/lib" "$HOME/bin/sys" "$HOME/.local/share" "$HOME/.local/bin")
    for dir in "${dirs[@]}"; do
        find "$dir" -maxdepth 1 -xtype l -delete 2>/dev/null || true
    done
}

cleanup_empty_home_symlinks() {
    for link in "$HOME"/*/; do
        [ -L "${link%/}" ] || continue
        # Skip wormholes - they're managed by the wormhole command
        [[ "$(basename "${link%/}")" == "wormhole" ]] && continue
        local target
        target=$(readlink -f "${link%/}")
        [ -d "$target" ] || continue
        [ -z "$(ls -A "$target" 2>/dev/null)" ] && rm "${link%/}"
    done
}

cleanup_broken_links
cleanup_empty_home_symlinks

#--[UTILITIES]----------------------------------

setup_sys() {
    local user_dir="$1"
    [ -d "$user_dir" ] || return 0
    mkdir -p "$user_dir/sys"
}

link_contents() {
    local source_dir="$1"
    local target_dir="$2"

    [ -d "$source_dir" ] || return 0

    for item in "$source_dir"/*; do
        [ -e "$item" ] || continue
        [ -d "$item" ] && continue
        ln -sf "$item" "$target_dir/$(basename "$item")"
    done
}

link_contents_sudo() {
    local source_dir="$1"
    local target_dir="$2"

    [ -d "$source_dir" ] || return 0

    for item in "$source_dir"/*; do
        [ -e "$item" ] || continue
        [ -d "$item" ] && continue
        sudo ln -sf "$item" "$target_dir/$(basename "$item")"
    done
}

sync_system_links() {
    link_contents_sudo "$HOME/bin/sys" "/usr/local/bin"
    link_contents_sudo "/home/linuxbrew/.linuxbrew/bin" "/usr/local/bin"
    link_contents_sudo "$HOME/.config/systemd/sys" "/etc/systemd/system"
    link_contents_sudo "$HOME/.config/autostart/sys" "/etc/xdg/autostart"
    link_contents_sudo "$HOME/.local/share/applications/sys" "/usr/share/applications"
    sudo systemctl daemon-reload
}

#--[BIN]----------------------------------------

setup_sys "$HOME/bin"
ln -sfn "$HOME/.local/bin" "$HOME/bin/local" 2>/dev/null || true
link_contents "$TOOLS/bin" "$HOME/bin"
link_contents "$PROJECTS/scripts" "$HOME/bin"
# $BASHRC/bin is now in PATH directly - no symlinks needed
link_contents "$TOOLS/bin/lib" "$HOME/bin/lib"
link_contents "$BASHRC/bin/lib" "$HOME/bin/lib"

# UV tools → ~/.local/bin
if command -v uv &>/dev/null; then
    for tool_bin in "$HOME/.local/share/uv/tools"/*/bin/*; do
        [ -x "$tool_bin" ] || continue
        ln -sf "$tool_bin" "$HOME/.local/bin/$(basename "$tool_bin")"
    done
fi

#--[SYSTEMD]------------------------------------

if [ -d "$HOME/.config/systemd" ]; then
    setup_sys "$HOME/.config/systemd"
    [ -L "$HOME/.config/systemd/user" ] || ln -sf . "$HOME/.config/systemd/user"
fi
link_contents "$BASHRC/storage/services" "$HOME/.config/systemd"

for svc in "$BASHRC/storage/services"/*.service; do
    name=$(basename "$svc")
    if ! systemctl --user is-enabled "$name" &>/dev/null; then
        systemctl --user enable "$name" 2>/dev/null || true
    fi
done

#--[AUTOSTART]----------------------------------

setup_sys "$HOME/.config/autostart"

#--[XDG]----------------------------------------

ln -sf "$BASHRC/modules/universal/xdg.sh" "$HOME/.config/user-dirs.dirs"

#--[FONTS]--------------------------------------

[ -d "$HOME/.config/fonts" ] && ln -sfn "$HOME/.config/fonts" "$HOME/.local/share/fonts"

#--[NIX APPLICATIONS]-------------------------------

link_contents "$HOME/.nix-profile/share/applications" "$HOME/.local/share/applications"

#--[MEDIA GALLERY]-------------------------------

sync_media_gallery() {
    [ -d "$MEDIA" ] || return 0

    # Clear existing symlinks (real files untouched)
    find "$PICTURES_GALLERY" "$VIDEOS_GALLERY" "$AUDIO_GALLERY" "$WALLPAPERS_GALLERY" \
        -maxdepth 1 -type l -delete 2>/dev/null || true

    while IFS= read -r -d '' file; do
        local rel="${file#$MEDIA/}"
        local name="${rel//\//-}"
        local ext="${file##*.}"

        case "${ext,,}" in
            png|jpg|jpeg|gif|webp|svg|tiff|tif|bmp|kra|xcf|psd)
                ln -sf "$file" "$PICTURES_GALLERY/$name" ;;
            mp4|mkv|webm|mov|avi|mpeg|mpg|flv|wmv)
                ln -sf "$file" "$VIDEOS_GALLERY/$name" ;;
            mp3|flac|wav|ogg|opus|aac|m4a|wma)
                ln -sf "$file" "$AUDIO_GALLERY/$name" ;;
        esac
    done < <(find "$MEDIA" \
        -not -path "$MEDIA/gallery/*" \
        -not -ipath "$MEDIA/screenshots/*" \
        -not -ipath "$MEDIA/wallpapers/*" \
        -not -ipath "$MEDIA/wallpaper/*" \
        -not -ipath "$MEDIA/wpp/*" \
        -type f -print0 2>/dev/null)
}

sync_media_gallery

#--[WALLPAPERS GALLERY]--------------------------

sync_wallpapers_gallery() {
    local wpp_dir=""
    for _d in wallpapers Wallpapers wallpaper Wallpaper wpp Wpp; do
        [ -d "$MEDIA/$_d" ] && wpp_dir="$MEDIA/$_d" && break
    done
    [ -n "$wpp_dir" ] || return 0

    mkdir -p "$WALLPAPERS_GALLERY"

    while IFS= read -r -d '' file; do
        local rel="${file#$wpp_dir/}"
        local name="${rel//\//-}"
        ln -sf "$file" "$WALLPAPERS_GALLERY/$name"
    done < <(find "$wpp_dir" -type f -print0 2>/dev/null)
}

sync_wallpapers_gallery

#--[WORKSPACE ↔ MEDIA CROSSLINKS]---------------

sync_workspace_media() {
    [ -d "$WORKSPACE" ] || return 0
    [ -d "$MEDIA" ] || return 0

    for ws_dir in "$WORKSPACE"/*/ "$WORKSPACE"/*/*/; do
        [ -d "$ws_dir" ] || continue
        local rel="${ws_dir%/}"; rel="${rel#$WORKSPACE/}"
        local media_dir="$MEDIA/$rel"
        [ -d "$media_dir" ] || continue

        # Workspace side: media/ or local-media/ → Media/project
        local ws_link="${ws_dir%/}/media"
        if [ -e "$ws_link" ] && [ ! -L "$ws_link" ]; then
            ws_link="${ws_dir%/}/local-media"
        fi
        ln -sfn "$media_dir" "$ws_link"

        # Media side: workspace/ → Workspace/project
        ln -sfn "${ws_dir%/}" "$media_dir/workspace"
    done
}

sync_workspace_media

