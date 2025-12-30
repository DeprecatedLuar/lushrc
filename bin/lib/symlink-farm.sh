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

cleanup_broken_links

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
link_contents "$BASHRC/bin" "$HOME/bin"
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

#--[AUTOSTART]----------------------------------

setup_sys "$HOME/.config/autostart"

#--[XDG]----------------------------------------

ln -sf "$BASHRC/modules/universal/xdg.sh" "$HOME/.config/user-dirs.dirs"

#--[FONTS]--------------------------------------

[ -d "$HOME/.config/fonts" ] && ln -sfn "$HOME/.config/fonts" "$HOME/.local/share/fonts"

#--[NIX APPLICATIONS]-------------------------------

link_contents "$HOME/.nix-profile/share/applications" "$HOME/.local/share/applications"

#--[WALLPAPERS]----------------------------------

for subdir in "$XDG_PICTURES_DIR/wallpapers"/*/; do
    link_contents "$subdir" "$XDG_PICTURES_DIR/wallpapers"
done

