# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**pmo** (PostMarketOS power management) is a single POSIX shell script (`bin/pmo`) targeting a Qualcomm phone running PostmarketOS. It manages display, on-screen keyboard (buffyboard), hardware button daemon (triggerhappy), backlight, and charge speed — all without root, via udev rules and group permissions set up by `setup.sh`.

The phone is `qingyou`, reachable at `172.16.42.1` via USB tethering. Sync changes with:
```bash
rsync -av bin/pmo 172.16.42.1:/home/luar/.config/lushrc/bin/pmo
rsync -av bin/lib/pmo/setup.sh 172.16.42.1:/home/luar/.config/lushrc/bin/lib/pmo/setup.sh
```

## Architecture

Two files:

- **`bin/pmo`** — the main command. All subcommands in a single `case` block. Brightness operates in raw kernel units internally; `set_brightness` accepts percentage (0–100) or relative (`+N`/`-N`). Sleep saves raw brightness to `/tmp/pmo-brightness` and restores it on wake.

- **`bin/lib/pmo/setup.sh`** — one-time (idempotent) provisioning. Run on the phone as the user (uses `doas`). Detects init system at the top, used throughout. Installs deps via `apk`, builds `thd` from source if missing, writes udev rules, sets up the triggerhappy systemd user service, and configures autologin.

## Key sysfs paths (Qualcomm hardware)

| Purpose | Path |
|---|---|
| Framebuffer blank | `/sys/class/graphics/fb0/blank` (1=blank, 0=unblank) |
| Backlight | `/sys/class/backlight/backlight/brightness` + `max_brightness` |
| Charge limit | `/sys/class/power_supply/qcom-smbchg-usb/input_current_limit` (µA) |

## Important behaviors

- **Framebuffer blanking is overridden by keypresses** — the Linux VT layer auto-unblanks on any TTY input. `pmo sleep` therefore sets backlight to 0 (the real visual blank) in addition to writing to `fb0/blank`.
- **`/dev/uinput` is recreated on every boot** as `root:root 600` — the udev rule in `setup.sh` uses `RUN+=chgrp/chmod` (not `GROUP=`/`MODE=`) to reliably set permissions after module load.
- **triggerhappy runs as a systemd user service** with `Restart=always` and an explicit `PATH` env that includes `$PMO_DIR` so `pmo` is resolvable without a login shell.
- **Default button config** is only written if `buttons.conf` doesn't exist (idempotent). Uses absolute paths (`$PMO_DIR/pmo`) since thd's environment has no `~/bin`.

## triggerhappy button config

Located at `~/.config/triggerhappy/buttons.conf` on the phone. Edit via `pmo -e`. Format: `KEY_NAME  1  command` (1 = keypress).
