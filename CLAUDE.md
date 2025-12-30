# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**LUSHRC** (Luar's Ultimate SHell - remastered cut) is a modular, self-healing shell configuration framework. It's a portable dotfiles system emphasizing Unix philosophy, modularity, and intelligent automation.

**Installation**: One-liner bootstrap via curl | bash, self-updates via Git.

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
  └→ zoxide init + completions
```

**Key Environment Variables**:
- `BASHRC=$HOME/.config/lushrc` - Root of all configs
- `LIBDIR=$BASHRC/bin/lib` - Shell script libraries
- `WORKSPACE`, `TOOLS`, `PROJECTS` - Developer workspace directories
- XDG-compliant directories in `xdg.sh`

### Self-Healing Symlink System

On every bashrc reload (or explicit `reload` command):
1. `symlink-farm.sh` runs automatically
2. Removes all broken symlinks from ~/bin, ~/.local/bin, etc.
3. Recreates symlinks from:
   - `$BASHRC/bin/*` → `~/bin/`
   - `$TOOLS/bin/*` → `~/bin/`
   - UV tools, systemd configs, fonts, applications
4. Makes all scripts executable
5. Refreshes command hash

**Idempotent**: Can run multiple times safely.

### Navigation Engine (nav-engine.sh)

Universal path resolver powering `tx`, `yoink`, `wormhole`, and enhanced `z`:

**TX Index Shorthand**:
```
w/  → $WORKSPACE/
t/  → $TOOLS/
f/  → $TOOLS_FOREIGN/
h/  → $TOOLS_HOMEMADE/
c/  → $HOME/.config/
b/  → $HOME/bin/
sb/ → /usr/local/bin/
d/  → $HOME/Downloads/
doc/→ $HOME/Documents/
```

**Resolution Order**:
1. TX index expansion (if matches prefix)
2. Zoxide fuzzy history lookup
3. Path expansion (~/ → $HOME/)
4. Returns single absolute path

**Usage in tools**:
```bash
tx w/projects ~/backup      # Move using TX indices
yoink ssh://host:w/file .   # Remote pull with nav-engine on both ends
wormhole t/script b/alias   # Create symlink using shortcuts
```

### Package Management (SAT/notsat)

Multi-source package manager wrapper:

**Sources**: cargo, npm, uv, system (apt/apk/pacman/dnf), GitHub releases, SAT scripts

**Manifests**:
- System: `~/.local/share/sat/manifest` (tool=source)
- Session: `~/.local/share/sat/shell/<SESSION_ID>` (tool:source:pid)

**Key scripts**:
- `bin/notsat` - Main entry point
- `bin/lib/sat/` - Source-specific installers (cargo.sh, npm.sh, gh.sh, etc.)
- `bin/lib/sat/common.sh` - Shared utilities

**Features**: Fallback install order, source detection, session isolation

## Key Utilities

### Command Launcher (hotline)
Tmux-based rofi launcher with multiple modes:
- **Normal**: Run, capture output, notify
- **hold**: Keep pane open for interactive commands
- **mute**: Silent execution
- **dial**: Prompt for input via rofi
- **sudo**: Password prompt via rofi

History: `/tmp/hotline_history` with `!!` expansion

### File Operations
- **pack/unpack**: Universal archive handling (tar, zip, 7z, etc.)
- **tx**: Navigation + file moving with undo (undo data in `/tmp/tx-undo-$USER/`)
- **yoink/yeet**: Remote file transfer (rsync over SSH)
- **dock/undock**: SSHFS mounting with nav-engine paths

### Path Management (path utility)
Double-symlink chain for ephemeral PATH additions:
```
Original → /tmp/path/basename (ephemeral) → ~/bin/xname (persistent)
```
Auto-cleanup via /tmp wipe + reload's broken link removal.

### System Tools
- **vibecheck**: Port scanning, process finding, hardware info, system metrics
- **conf**: Quick access to config files
- **lush**: Self-management (update, status, version, root)

## Development Patterns

### Adding New Commands

1. Create script in `bin/` with `#!/usr/bin/env bash`
2. Make executable: `chmod +x bin/newcmd`
3. Run `reload` to create symlink in `~/bin/`
4. For system-wide access: `lush root newcmd`

### Adding Libraries

Place in `bin/lib/` with `.sh` extension. Source via:
```bash
source "$LIBDIR/library-name.sh"
```

### Adding Configuration Modules

- **Universal** (always loaded): `modules/universal/`
- **Defaults** (program selections): `modules/defaults/`
- **Local** (user-specific): `modules/local.sh` (auto-created, git-ignored)

Add sourcing in `modules/universal/source.sh` for universal modules.

### Using nav-engine in Scripts

```bash
source "$LIBDIR/nav-engine.sh"

# Get absolute path from TX index or zoxide
dest=$(nav-engine "$1")

# Optional: Enable logging
dest=$(nav-engine --log "$1")
```

### SAT Package Source

Create installer in `bin/lib/sat/<source>.sh` with functions:
- `_sat_<source>_install PACKAGE`
- `_sat_<source>_uninstall PACKAGE`
- `_sat_<source>_detect PACKAGE` (returns source name if package is from this source)

Register in `bin/lib/sat/common.sh` arrays.

## Testing & Maintenance

**Reload after changes**: `reload` or `source ~/.bashrc`

**System-wide symlink sync**: `reload --system` (requires sudo)

**Self-update**: `lush update` (git pull with change detection)

**Check modifications**: `lush status` (git status wrapper)

**Version info**: `lush version` (commit + age)

## Important Conventions

- **Single source of truth**: `$BASHRC` variable points to repo root
- **Self-healing**: Broken links cleaned automatically on reload
- **XDG compliance**: Respect standard directory variables
- **Idempotency**: All sync/setup scripts can run multiple times
- **Grace handling**: Scripts succeed even if directories don't exist
- **Configuration-as-code**: Shell scripts, not YAML/TOML

## Remote Operations

SSH integration allows nav-engine on remote hosts:
```bash
# Remote nav-engine is bootstrapped via: cat nav-engine.sh | ssh host bash -s -- w/path
yoink ssh://host:w/project/file.txt .
dock host w/workspace ~/remote-workspace
```

Enhanced SSH wrapper (`assh`) enables password prompts in non-interactive shells.

## File Locations

**Configs**:
- Main: `bashrc`, `profile`
- Modules: `modules/universal/`, `modules/defaults/`
- Libraries: `bin/lib/`

**Runtime Data**:
- SAT manifests: `~/.local/share/sat/`
- TX undo: `/tmp/tx-undo-$USER/`
- Hotline history: `/tmp/hotline_history`
- Ephemeral symlinks: `/tmp/path/`

**User Overrides**:
- `modules/local.sh` (auto-created, git-ignored)
