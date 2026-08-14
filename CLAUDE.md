# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**LUSHRC** (Luar's Ultimate SHell - remastered cut) is a modular, self-healing shell configuration framework. It's a portable dotfiles system emphasizing Unix philosophy, modularity, and intelligent automation.

**Installation**: One-liner bootstrap via curl | bash, self-updates via Git.

## Quick Reference

```bash
reload              # Apply changes to shell config
lush status         # Check git status of lushrc
lush update         # Pull latest changes
hotline help        # Command launcher help
```

## Architecture

### Configuration Loading Pipeline

```
~/.bashrc (system)
  ↓ sources
$BASHRC/bashrc (lushrc main)
  ↓ sources
modules/universal/source.sh
  ├→ paths.sh (sets BASHRC, XDG_*, WORKSPACE, TOOLS, etc.)
  ├→ xdg.sh (XDG directory initialization)
  ├→ defaults/defaults.sh (EDITOR, BROWSER, TERMINAL selections)
  ├→ aliases.sh (shell shortcuts)
  ├→ local.sh (user-specific, git-ignored)
  └→ zoxide init + z() override via bin/lib/shared/z-wrapper.sh
```

**Key Environment Variables**:
- `BASHRC=$HOME/.config/lushrc` - Root of all configs (single source of truth)
- `LIBDIR=$BASHRC/bin/lib` - Shell script libraries
- `WORKSPACE=$HOME/Workspace` - Root workspace directory
- `TOOLS=$WORKSPACE/tools` - Cloned repos and external tools
- `PROJECTS=$WORKSPACE/dev` - Your active development projects
- `MEDIA=$HOME/Media` - Flat media hub; subfolders are project/tool-named
- `MEDIA_GALLERY=$MEDIA/gallery` - Auto-populated symlink gallery (`pictures/`, `videos/`, `audio/`)
- XDG dirs (`XDG_PICTURES_DIR`, `XDG_VIDEOS_DIR`, `XDG_MUSIC_DIR`) all resolve to `$MEDIA`

### bin/lib/ Structure

Libraries are organized by ownership, not by type:

```
bin/lib/
  shared/     — libraries used by multiple binaries (nav-engine, net, ssh-conn, spinner, z-wrapper, gh-install)
  reload/     — shell reload machinery (reload.sh, symlink-farm.sh, ensure-dirs.sh, sync-mime-defaults.sh, downloads-rotation.sh)
  vibecheck/  — helpers owned exclusively by vibecheck
  sat/        — helpers owned exclusively by sat
  serve/      — assets owned exclusively by serve (share.html)
  pmo/        — helpers owned exclusively by pmo
  yeetyoink/  — helpers owned jointly by the yeet/yoink twins
  input/      — UI assets for input prompts (rofi .rasi + .sh)
```

**Rule**: if a file is used by more than one binary → `shared/`. If it belongs to exactly one → its own subdir. Exception: twin binaries that are two directions of one operation (`yeet`/`yoink`) share a single named subdir rather than leaking their internals into `shared/`.

### Self-Healing Symlink System

On every `reload`:
1. `bin/lib/reload/symlink-farm.sh` removes broken symlinks from `~/bin`, `~/.local/bin`, etc.
2. Recreates symlinks: `$BASHRC/bin/*` → `~/bin/`, `$TOOLS/bin/*` → `~/bin/`
3. `$BASHRC/bin` is on `$PATH` directly — no symlinks needed for bin/ scripts themselves
4. Syncs UV tools, systemd configs, fonts, applications, media gallery

**Idempotent**: safe to run multiple times.

### Navigation Engine

`bin/lib/shared/nav-engine.sh` — universal path resolver powering `tx`, `pw`, `yoink`, `yeet`, `wormhole`, `z`, `peek`, `edit`, `scav`.

**Flags**: `-f`/`--file` enables file resolution (default is directory-only), `--log` enables debug output.

**Nav Index Shorthand**:
```
w/  → $WORKSPACE/    t/  → $TOOLS/       c/  → $HOME/.config/
b/  → $HOME/bin/     d/  → $HOME/Downloads/   l/ → $HOME/.local/
sb/ → /usr/local/bin/   doc/ → $DOCUMENTS/    etc/ → /etc/
med/|pic/|vid/ → $MEDIA/
```

**Resolution Order**: nav index expansion → exact path → right-to-left fuzzy decomposition → glob matching with scoring → zoxide fallback.

**Using nav-engine in scripts**:
```bash
dest=$("$LIBDIR/shared/nav-engine.sh" "$1")          # directory resolution
dest=$("$LIBDIR/shared/nav-engine.sh" -f "$1")       # file-aware resolution
dest=$("$LIBDIR/shared/nav-engine.sh" --log "$1")    # with debug output
```

Remote bootstrapping: `yoink`/`yeet` pipe `nav-engine.sh` via stdin to SSH for remote path resolution.

## Key Utilities

### Command Launcher (hotline)
CLI-first tmux-based command runner. Rofi serves as optional GUI input.

```bash
hotline <cmd>       # Execute command (captures output, notifies)
hotline hold <cmd>  # Keep pane open after completion
hotline mute <cmd>  # Silent execution
hotline dial <cmd>  # Prompt for input, pipe to command
hotline sudo <cmd>  # Password prompt via rofi
hotline pickup      # Attach to tmux session
```

History: `/tmp/hotline_history` with `!!` and `!-N` expansion.

### LAN File Sharing (serve / evres)

```bash
serve                      # serve CWD at http://<local-ip>:8080
evres .13                  # consume from 192.168.1.13:8080
evres .13:9000 --all       # custom port, download all non-interactively
```

HTML template: `bin/lib/serve/share.html`.

### SSH Tools (yoink, yeet, dock, lsh)

Unified connection format: `[-p PORT] [-l USER] [user@]host[:port]`

`.N` subnet shorthand via `bin/lib/shared/net.sh` works across all SSH tools:
```bash
yoink .17 w/project .      # pull from LAN host using nav-engine path
yeet --rm data.sql .17     # push and delete local source
dock user@host:port w/proj # SSHFS mount → ~/hostname-subdir + /tmp/dock/
```

`lsh` — transparent SSH wrapper adding `.N` shorthand, `--password` flag (sshpass), and askpass support for non-interactive shells. The interactive `ssh`/`lsh` shell functions mark plain `ssh <host>` calls for local tmux staging, Mosh preference, and pre-establishment SSH fallback. Smart interactive connections use a ten-second establishment timeout (configurable with `LSH_CONNECT_TIMEOUT`); after a slow timeout, an ICMP response triggers one unbounded plain-SSH retry. Established sessions are not limited. Staged sessions use canonical zero-based names (`lsh-host-0`, `lsh-host-1`, etc.) and carry `@lsh_managed=1` metadata for filtering. Their tmux window status shows `mosh|ssh · user@host`, with `Nms` right-aligned and refreshed asynchronously every five seconds when ICMP is available. Scripts, PTY automation, SSH flags, pipes, and remote commands remain direct SSH. Wrapper policy flags: `--no-tmux` skips staging, `--no-mosh` forces SSH while retaining staging, and `--raw` bypasses lsh entirely.

### Media Tools

**rec** — Wayland screen/audio recorder:
```bash
rec screen [--mic|--mute]  # screen recording variants
rec audio / rec mic        # audio-only
rec stop / rec delete      # save or discard
```
State in `/tmp/rec.state`. Audio format auto-detected (pulse vs pipewire).

**tranz** — universal converter (ffmpeg / ImageMagick / whisper-cpp / libreoffice):
```bash
tranz video.mkv audio.flac    # extract audio
tranz ./*.png .webp           # batch image convert
tranz video.mp4 transcript.txt # transcribe via whisper
```
Whisper config (model, device, compute type) hardcoded at top of script.

### Other Tools
- **tx**: Navigation + file moving with undo (`/tmp/tx-undo-$USER/`)
- **pw**: Path wrapper — `pw cat c/lushrc/bashrc` or inline `cat $(pw c/file)`
- **pack/unpack**: Universal archive handling
- **vibecheck**: Port scanning, process finding, hardware info, system metrics
- **conf**: Quick access to config files
- **lush**: Self-management (`update`, `status`, `version`, `root`)
- **gh-install** (`bin/lib/shared/gh-install.sh`): `gh_install <binary> <user/repo>` — lazy-installs GitHub-hosted binaries via the-satellite. Used by `tcpeek`, `netboop`, `dredge`, `dots`.

## Development Patterns

### Adding a New Command

1. Create `bin/newcmd` with `#!/usr/bin/env bash`, make executable
2. `reload` — symlink appears in `~/bin/` automatically
3. For system-wide (sudo) access: `lush root newcmd`

### Adding a Library

- **Shared** (multiple commands use it): `bin/lib/shared/newlib.sh`, source via `source "$LIBDIR/shared/newlib.sh"`
- **Command-specific**: `bin/lib/cmdname/helper.sh`

Key shared libs:
- `shared/net.sh` — `local_ip()`, `expand_local_ip()` (`.N` → full IP)
- `shared/spinner.sh` — `spin "Label" $PID` — blocks until PID exits
- `shared/nav-engine.sh` — path resolution (see above)
- `shared/gh-install.sh` — `gh_install <bin> <user/repo>` lazy installer

### Adding Configuration Modules

- **Universal** (always loaded): `modules/universal/`, add sourcing in `source.sh`
- **Defaults** (program selections): `modules/defaults/`
- **Local** (user-specific, never committed): `modules/local.sh`

## Testing & Maintenance

```bash
reload               # Apply changes, rebuild symlinks
reload --system      # Also sync system-level symlinks (requires sudo)
lush update          # git pull + reload
lush status          # git status
lush version         # commit + age
```

## Important Conventions

- **Absolute paths only**: all paths anchored to `$BASHRC`, `$LIBDIR`, etc.
- **Idempotency**: reload scripts can run multiple times safely
- **Grace handling**: `|| true` / `|| return 0` — scripts succeed even if dirs don't exist
- **Configuration-as-code**: shell scripts, not YAML/TOML
- **Git-ignored customization**: `modules/local.sh` for user-specific overrides

## Architecture Reference

### Reload Workflow

```
reload command
  ↓
source ~/.bashrc
  ↓
$LIBDIR/reload/reload.sh
  ├─ ensure-dirs.sh       (mkdir -p all workspace dirs)
  ├─ chmod +x             (bin/, TOOLS/bin/)
  ├─ symlink-farm.sh
  │   ├─ cleanup broken symlinks
  │   ├─ link $TOOLS/bin/* → ~/bin/
  │   ├─ sync UV tools, fonts, Nix apps, systemd
  │   ├─ sync_media_gallery → $MEDIA_GALLERY/{pictures,videos,audio,wallpapers}
  │   └─ sync_workspace_media → cross-links $WORKSPACE ↔ $MEDIA
  ├─ sync-mime-defaults.sh
  └─ sync_system_links    (if --system flag, sudo)
```

### Critical File Dependency Map

| File | Used By | Purpose |
|------|---------|---------|
| `bashrc` | Shell init | Entry point, sets `$BASHRC`, sources modules |
| `modules/universal/paths.sh` | Everything | Defines all env vars incl. `$LIBDIR` |
| `bin/lib/shared/nav-engine.sh` | tx, pw, yoink, yeet, z, peek, edit, scav, wormhole | Path resolution engine |
| `bin/lib/shared/net.sh` | dock, yoink, yeet, evres, lsh, scav | LAN IP detection + `.N` shorthand |
| `bin/lib/shared/ssh-conn.sh` | yoink, yeet, dock | `parse_conn` → `CONN_*`, plus `conn_ssh`/`conn_ssh_pipe`/`conn_rsync` |
| `bin/lib/yeetyoink/remote.sh` | yoink, yeet | Remote path resolution + existence/tool probes |
| `bin/lib/yeetyoink/prompt.sh` | yoink, yeet | `confirm_block` transfer confirmation UI |
| `bin/lib/shared/spinner.sh` | dock, yoink | Terminal progress indicator |
| `bin/lib/shared/z-wrapper.sh` | `source.sh` (z function) | Enhanced zoxide wrapper |
| `bin/lib/shared/gh-install.sh` | tcpeek, netboop, dredge, dots | Lazy GitHub binary installer |
| `bin/lib/reload/reload.sh` | `reload` alias, `lush` | Orchestrates config refresh |
| `bin/lib/reload/symlink-farm.sh` | `reload.sh` | Symlink maintenance |
| `bin/hotline` | tmux | Async command launcher |
