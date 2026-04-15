#!/usr/bin/env sh
# Setup script for pmo - configures permissions for non-root access
set -e

UDEV_RULE="/etc/udev/rules.d/90-pmo.rules"
TH_CONF="$HOME/.config/triggerhappy"
PMO_PATH=$(command -v pmo) || { echo "Error: pmo not found in PATH" >&2; exit 1; }
PMO_DIR=$(dirname "$(realpath "$PMO_PATH")")

# Detect init system
if command -v systemctl >/dev/null 2>&1; then
    INIT=systemd
elif command -v rc-service >/dev/null 2>&1; then
    INIT=openrc
else
    echo "Warning: unknown init system, skipping autologin and service setup" >&2
    INIT=unknown
fi

# Install dependencies
for pkg in buffyboard libcap musl-locales git make gcc musl-dev linux-headers; do
    if ! apk info -e "$pkg" >/dev/null 2>&1; then
        echo "Installing $pkg..."
        if ! doas apk add --no-interactive "$pkg"; then
            echo "Error: Failed to install $pkg" >&2
            exit 1
        fi
    fi
done

# Build and install triggerhappy
if ! command -v thd >/dev/null 2>&1; then
    echo "Building triggerhappy..."
    cd /tmp
    rm -rf triggerhappy
    git clone --depth 1 https://github.com/wertarbyte/triggerhappy.git
    cd triggerhappy
    make
    doas cp thd th-cmd /usr/local/bin/
    rm -rf /tmp/triggerhappy
    echo "Installed thd to /usr/local/bin/"
fi

# Create triggerhappy config
mkdir -p "$TH_CONF"
[ -f "$TH_CONF/buttons.conf" ] || cat > "$TH_CONF/buttons.conf" << EOF
KEY_VOLUMEUP    1    notify-send "Volume Up"
KEY_VOLUMEDOWN  1    $PMO_DIR/pmo kb-switch
KEY_POWER       1    $PMO_DIR/pmo wake-switch
EOF

# Add user to required groups
doas adduser "$USER" video
doas adduser "$USER" input
doas adduser "$USER" plugdev 2>/dev/null || true

# Set UTF-8 locale
grep -q 'LANG=C.UTF-8' ~/.profile 2>/dev/null || echo 'export LANG=C.UTF-8' >> ~/.profile

# Allow setfont without root
doas setcap cap_sys_tty_config+ep /usr/sbin/setfont

# Suppress kernel messages on TTY (input registration, DRM debug noise)
doas sysctl -w kernel.printk='4 4 1 7'
grep -q 'kernel.printk' /etc/sysctl.conf 2>/dev/null || echo 'kernel.printk = 4 4 1 7' | doas tee -a /etc/sysctl.conf > /dev/null
echo 0 | doas tee /sys/module/drm/parameters/debug > /dev/null
echo 'options drm debug=0' | doas tee /etc/modprobe.d/drm-quiet.conf > /dev/null

# Load uinput module and persist across reboots
echo "Loading uinput module..."
doas modprobe uinput
case "$INIT" in
    systemd) echo "uinput" | doas tee /etc/modules-load.d/pmo.conf > /dev/null ;;
    openrc)  grep -q uinput /etc/modules 2>/dev/null || echo "uinput" | doas tee -a /etc/modules > /dev/null ;;
esac

# Udev rules for device access
echo "Creating udev rules..."
doas tee "$UDEV_RULE" > /dev/null << 'EOF'
# Display control
SUBSYSTEM=="graphics", KERNEL=="fb0", RUN+="/bin/chgrp video /sys%p/blank", RUN+="/bin/chmod g+w /sys%p/blank"
SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys%p/brightness", RUN+="/bin/chmod g+w /sys%p/brightness"
# Buffyboard - uinput access
KERNEL=="uinput", RUN+="/bin/chgrp input /dev/uinput", RUN+="/bin/chmod 0660 /dev/uinput"
KERNEL=="tty0", TAG+="uaccess"
# Triggerhappy - input event access
SUBSYSTEM=="input", TAG+="uaccess"
# Charge speed control
SUBSYSTEM=="power_supply", KERNEL=="qcom-smbchg-usb", RUN+="/bin/chgrp plugdev /sys%p/input_current_limit", RUN+="/bin/chmod g+w /sys%p/input_current_limit"
EOF
doas udevadm control --reload-rules
doas udevadm trigger

# Autologin on tty1
echo "Configuring autologin..."
case "$INIT" in
    systemd)
        AUTOLOGIN_DIR="/etc/systemd/system/getty@tty1.service.d"
        doas mkdir -p "$AUTOLOGIN_DIR"
        doas tee "$AUTOLOGIN_DIR/autologin.conf" > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
        doas systemctl daemon-reload
        ;;
    openrc)
        if ! grep -q "autologin $USER" /etc/inittab 2>/dev/null; then
            doas sed -i "s|^\(.*tty1.*agetty\)|\1 --autologin $USER|" /etc/inittab
        fi
        ;;
esac

# Triggerhappy service
echo "Configuring triggerhappy service..."
case "$INIT" in
    systemd)
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$HOME/.config/systemd/user/triggerhappy.service" << EOF
[Unit]
Description=Triggerhappy button daemon

[Service]
Environment=PATH=$PMO_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/bin/sh -c 'exec /usr/local/bin/thd --triggers $TH_CONF/ /dev/input/event*'
Restart=always

[Install]
WantedBy=default.target
EOF
        systemctl --user enable --now triggerhappy
        ;;
    openrc)
        doas tee /etc/init.d/triggerhappy > /dev/null << EOF
#!/sbin/openrc-run
command="/usr/local/bin/thd"
command_args="--triggers $TH_CONF/ /dev/input/event*"
command_user="$USER"
pidfile="/run/triggerhappy.pid"
command_background=true
EOF
        doas chmod +x /etc/init.d/triggerhappy
        doas rc-update add triggerhappy default
        doas rc-service triggerhappy start
        ;;
esac

# Trust LAN interface (same as desktop distro home zone default)
echo "Trusting LAN..."
if command -v nft >/dev/null 2>&1; then
    doas tee /etc/nftables.d/60_pmo.nft > /dev/null << 'EOF'
# pmo: trust LAN (wlan* is home network)
table inet filter {
    chain input {
        iifname "wlan*" accept comment "trust LAN"
    }
}
EOF
    doas nft -f /etc/nftables.nft
fi

# Disable WiFi power save globally (driver bugs can cause TX path to silently die)
NM_WIFI_CONF="/etc/NetworkManager/conf.d/wifi-powersave.conf"
if [ ! -f "$NM_WIFI_CONF" ]; then
    doas tee "$NM_WIFI_CONF" > /dev/null << 'EOF'
[connection]
wifi.powersave = 2
EOF
    doas systemctl reload NetworkManager 2>/dev/null || doas rc-service NetworkManager reload 2>/dev/null || true
fi

# Allow nmcli network-control without polkit seat (enables pmo wifi from SSH/scripts)
POLKIT_RULE="/etc/polkit-1/rules.d/50-pmo-network.rules"
doas tee "$POLKIT_RULE" > /dev/null << EOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.NetworkManager.network-control" &&
        subject.user == "$USER") {
        return polkit.Result.YES;
    }
});
EOF

# Verify uinput is accessible
if ! test -r /dev/uinput; then
    echo "Warning: /dev/uinput not accessible yet — reboot required for udev rules to take effect" >&2
fi

echo "Done. Reboot for group changes to take effect."
