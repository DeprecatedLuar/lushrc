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
  └→ zoxide init + completions
```

**Key Environment Variables**:
- `BASHRC=$HOME/.config/lushrc` - Root of all configs (single source of truth)
- `LIBDIR=$BASHRC/bin/lib` - Shell script libraries
- `WORKSPACE=$HOME/Workspace` - Root workspace directory
- `TOOLS=$WORKSPACE/tools` - Cloned repos and external tools
- `PROJECTS=$WORKSPACE/dev` - Your active development projects
- `DOCKER_DIR=$WORKSPACE/docker` - Docker configurations
- `SHARED=$WORKSPACE/shared` - Shared workspace resources
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

Universal path resolver powering `tx`, `pw`, `yoink`, `wormhole`, and enhanced `z`:

**Flags**: `-f`/`--file` enables file resolution (default is directory-only), `--log` enables debug output.

**Nav Index Shorthand**:
```
w/  → $WORKSPACE/          l/   → $HOME/.local/
t/  → $TOOLS/              lb/  → $HOME/.local/bin/
c/  → $HOME/.config/       pic/ → $XDG_PICTURES_DIR/
b/  → $HOME/bin/           vid/ → $XDG_VIDEOS_DIR/
sb/ → /usr/local/bin/      d/   → $HOME/Downloads/
doc/ → $DOCUMENTS/         etc/ → /etc/
```

**Resolution Order**:
1. Nav index expansion (if matches prefix)
2. Recursive case-insensitive fuzzy matching
3. Zoxide fuzzy history lookup
4. Returns single absolute path

**Usage in tools**:
```bash
tx w/dev ~/backup           # Move using nav indices
pw cat c/lushrc/bashrc      # Resolve file path and cat it
cat $(pw c/lushrc/bashrc)   # Inline substitution
yoink ssh://host:w/file .   # Remote pull with nav-engine on both ends
wormhole t/script b/alias   # Create symlink using shortcuts
```

**Resolution Implementation**: Nav-engine uses a sophisticated fuzzy matching algorithm:
1. Decomposes paths right-to-left (e.g., `proj/src/main` → tries `main`, then `src/main`, then full path)
2. Case-insensitive glob matching with intelligent scoring (depth penalty, length similarity, position bonuses)
3. Falls back to `find` for deeper searches if glob fails
4. Returns single best match or errors with suggestions

### Package Management (SAT/notsat)

Multi-source package manager wrapper with intelligent fallback and session isolation.

**Sources**: cargo, npm, uv, system (apt/apk/pacman/dnf), GitHub releases, nix, brew, SAT scripts

**Install Priority Order**:
- Permanent (system): `system → brew → nix → cargo → uv → npm → sat → gh`
- Temporary (shell): `brew → nix → cargo → uv → system → npm → sat → gh`

**Manifests**:
- System: `~/.local/share/sat/manifest` (tool=source, permanent installs)
- Session: `~/.local/share/sat/shell/<SESSION_ID>` (tool:source:pid, ephemeral per shell)
- Master: `~/.local/share/sat/shell/manifest` (tracks active shell sessions)

**Key scripts**:
- `bin/notsat` - Main entry point (handles install/uninstall/list/promote)
- `bin/lib/sat/` - Source-specific installers (cargo.sh, npm.sh, gh.sh, system.sh, etc.)
- `bin/lib/sat/common.sh` - Shared utilities, manifest management, colored output

**Features**:
- Fallback install order (tries multiple sources)
- Automatic source detection for existing binaries
- Session isolation (temp installs cleanup on shell exit)
- Promotion (move temp shell tools to permanent system)
- Colored output by source (Rust=red, Node=green, Python=blue, etc.)

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
hotline             # Open rofi prompt (GUI entry)
```

History: `/tmp/hotline_history` with `!!` and `!-N` expansion

### File Operations
- **pw**: Path wrapper — resolves nav indices inline (`pw cat c/lushrc/bashrc`) or via substitution (`cat $(pw c/file)`)
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
# Get absolute path from nav index or zoxide (directory-only)
dest=$("$LIBDIR/nav-engine.sh" "$1")

# File-aware resolution (-f flag)
dest=$("$LIBDIR/nav-engine.sh" -f "$1")

# Enable debug logging
dest=$("$LIBDIR/nav-engine.sh" --log "$1")
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

- **Single source of truth**: `$BASHRC` variable points to repo root - all paths are absolute from this anchor
- **Self-healing**: Broken links cleaned automatically on reload, missing directories auto-created
- **XDG compliance**: Respect standard directory variables (CONFIG_HOME, DATA_HOME, CACHE_HOME, etc.)
- **Idempotency**: All sync/setup scripts can run multiple times safely (symlink-farm, reload, ensure-dirs)
- **Grace handling**: Scripts succeed even if directories don't exist (`|| true`, `|| return 0`)
- **Configuration-as-code**: Shell scripts, not YAML/TOML - enables inline logic and conditional sourcing
- **Absolute paths only**: No relative paths in critical configs (prevents context-dependent bugs)
- **Fuzzy-first navigation**: Nav-engine prefers user intent (fuzzy matching) over exact paths
- **Git-ignored customization**: `modules/local.sh` for user-specific configs (never committed)

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

## Architecture Insights

### Component Interaction Flow

```
User Command (tx, yoink, pw, z, etc.)
    ↓
[nav-engine.sh] - Universal path resolver
    ├─ Nav index expansion (w/, t/, c/, etc.)
    ├─ Exact path check
    ├─ Right-to-left decomposition fuzzy search
    ├─ Glob matching with intelligent scoring
    └─ Zoxide fallback (if available)
    ↓
[Resolved Absolute Path]
    ↓
[Execute File/Navigation Operation]
```

### Reload Workflow

```
reload command
    ↓
source ~/.bashrc (re-sources all modules)
    ↓
$LIBDIR/reload.sh
    ├─ ensure-dirs.sh (mkdir -p all workspace directories)
    ├─ chmod +x (all scripts in bin/, TOOLS/bin/)
    ├─ symlink-farm.sh
    │   ├─ Cleanup: Remove broken symlinks from ~/bin, ~/.local/bin
    │   ├─ Link: $TOOLS/bin/* → ~/bin/
    │   ├─ Link: $BASHRC/bin/lib/* → ~/bin/lib/
    │   ├─ Link: UV tools → ~/.local/bin/
    │   └─ Link: Nix apps, fonts, wallpapers
    └─ Optional: sync_system_links (if --system/-s flag, requires sudo)
```

### Critical File Dependency Map

| File | Depends On | Used By | Purpose |
|------|-----------|---------|---------|
| `bashrc` | None (entry point) | Shell init | Sets BASHRC, sources modules |
| `modules/universal/paths.sh` | `xdg.sh` | Everything | Defines all environment vars |
| `bin/lib/nav-engine.sh` | `paths.sh` (for env vars) | tx, pw, yoink, z, wormhole | Path resolution engine |
| `bin/lib/symlink-farm.sh` | `paths.sh` | `reload.sh` | Maintains symlink consistency |
| `bin/lib/reload.sh` | `ensure-dirs.sh`, `symlink-farm.sh` | `reload` alias | Orchestrates config refresh |
| `bin/notsat` | `bin/lib/sat/*` | User package management | Multi-source package installer |
| `bin/hotline` | tmux | Async task execution | Command launcher with notifications |

### Why Nav-Engine is Central

Nav-engine is the **architectural keystone** of lushrc:
- **Every navigation tool depends on it**: tx, yoink, pw, z, wormhole all call nav-engine.sh
- **Enables shorthand everywhere**: Users can type `w/dev` instead of full paths
- **Fuzzy matching reduces friction**: No need to remember exact names
- **Remote operations work**: Can bootstrap nav-engine via SSH for yoink/dock
- **Consistent behavior**: Single resolution algorithm ensures predictable results

Without nav-engine, every tool would implement its own path logic (DRY violation).

### Why Symlink-Farm is Self-Healing

Symlink-farm maintains command availability through:
1. **Idempotent cleanup**: Removes broken links first (safe to run repeatedly)
2. **Multiple sources**: Links from both BASHRC/bin and TOOLS/bin
3. **Automatic sync**: Runs on every reload (after git pull, config changes)
4. **UV integration**: Detects and links uv-installed tools
5. **System-level option**: Can sync to /usr/local/bin with sudo

This eliminates "command not found" errors after moving/deleting repos.

### Workspace Organization (Current Structure)

```
Workspace/
├── dev/              # Your active code projects (renamed from projects/)
│   └── <repos>       # Git repos you're developing
├── tools/            # External tools and cloned repos (not actively developing)
│   └── bin/          # Tool binaries (symlinked to ~/bin)
├── docker/           # Docker configurations and compose files
├── krita/            # Krita art projects (.kra files)
├── blender/          # Blender 3D projects (.blend files)
├── kdenlive/         # Kdenlive video projects
├── audacity/         # Audacity audio projects
└── shared/           # Shared workspace resources
```

**Design Rationale**: Tool-specific folders (krita/, blender/, etc.) organize by file format since each tool produces distinct project files. `dev/` contains code repos, `tools/` contains dependencies/external repos.
