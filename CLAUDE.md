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
  └→ zoxide init + z() override via system/shared/z-wrapper.sh
```

**Key Environment Variables**:
- `BASHRC=$HOME/.config/lushrc` - Root of all configs (single source of truth)
- `SYSDIR=$BASHRC/system` - Always-shipped shell-init dependencies (`shared/`, `reload/`)
- `LIBDIR=$BASHRC/bin/lib` - Lazily-installed tool implementations
- `WORKSPACE=$HOME/Workspace` - Root workspace directory
- `TOOLS=$WORKSPACE/tools` - Cloned repos and external tools
- `PROJECTS=$WORKSPACE/dev` - Your active development projects
- `MEDIA=$HOME/Media` - Flat media hub; subfolders are project/tool-named
- `MEDIA_GALLERY=$MEDIA/gallery` - Auto-populated symlink gallery (`pictures/`, `videos/`, `audio/`)
- XDG dirs (`XDG_PICTURES_DIR`, `XDG_VIDEOS_DIR`, `XDG_MUSIC_DIR`) all resolve to `$MEDIA`

### system/ vs bin/lib/ — eager vs lazy

`system/` and `bin/lib/` look similar but mean opposite lifecycles:

```
system/           always ships — hard dependency of shell init
  shared/         nav-engine, net, ssh-conn, spinner, z-wrapper, gh-install
  reload/         reload.sh, symlink-farm.sh, ensure-dirs.sh, sync-mime-defaults.sh, downloads-rotation.sh

bin/<name>              pointer, zero logic — a generated stub or a gh_install shadow
bin/lib/<name>/main.sh  mandatory entrypoint — makes <name> a tool, gets a stub
bin/lib/<name>/         no main.sh — a library, never gets a stub
```

lushrc's long-term direction is to ship only stubs, with tool implementations installed on
demand (`lush install`); each tool eventually becomes its own repo, at which point `bin/<name>`
stops changing at all — only what's behind it moves. `system/` never participates in that: it's
what shell init and `reload` themselves depend on, so it can't be lazy.

**The `main.sh` rule is the only discriminator.** A directory under `bin/lib/` with `main.sh` is
a tool and gets an auto-generated `bin/<name>` stub. Without it, the directory is a library
(`shared/`-style, but tool-scoped) and is never scanned or exposed on `PATH`. This is deliberately
not inferred from filenames or exec bits — e.g. `bin/lib/lsh/` holds extensionless files
(`mosh-client`, `ssh-askpass`, `latency`) that impersonate external binaries on purpose; they stay
inert internal helpers precisely because only `main.sh` is ever promoted.

**Single-file tools stay flat in `bin/`** until they earn a split — real internal seams, the way
`cronotrigger`, `yeet`/`yoink`, and `lsh` earned theirs. A tool that's still one file has nothing
to gain from `bin/lib/<name>/main.sh` alone.

**Twin binaries** that are two directions of one operation (`yeet`/`yoink`) get two tool dirs
(`bin/lib/yeet/main.sh`, `bin/lib/yoink/main.sh`) sharing one library dir (`bin/lib/yeetyoink/`,
no `main.sh`) — never a single dir with either symlink tricks or `$0`-branching, both of which
would violate the one-file-one-role rule.

**Cross-boundary dependencies are declared, not left implicit** — a header comment naming what a
`main.sh` reaches outside its own directory:
```bash
# shared: net.sh ssh-conn.sh      # this tool's dependency on system/shared/
# needs: yeetyoink                # this tool's dependency on a sibling library dir
```
`grep -rn '^# shared:\|^# needs:' bin/lib/` gives the full cross-tool dependency graph in one
command — the blast radius for any future extraction to a standalone repo.

### Self-Healing Symlink System

On every `reload`:
1. `system/reload/symlink-farm.sh` removes broken symlinks from `~/bin`, `~/.local/bin`, etc.
2. `sync_tool_stubs()` scans `bin/lib/*/main.sh` and generates a `bin/<name>` stub for any tool
   that doesn't have one yet. Create-only — it never deletes a stub, since an absent
   `bin/lib/<tool>/` is the normal state for an as-yet-uninstalled lazy tool.
3. Recreates symlinks: `$BASHRC/bin/*` → `~/bin/`, `$TOOLS/bin/*` → `~/bin/`
4. `$BASHRC/bin` is on `$PATH` directly — no symlinks needed for bin/ scripts themselves
5. Syncs UV tools, systemd configs, fonts, applications, media gallery

**Idempotent**: safe to run multiple times.

### Tool Lifecycle (lush install / rm / list)

```bash
lush list              # every tool tracked under bin/lib/*/main.sh: installed or available
lush install <tool>    # restore bin/lib/<tool>/ from the git tree (errors on unknown tool)
lush install -A        # install every available tool
lush rm <tool>         # delete bin/lib/<tool>/ — refuses if it has uncommitted changes
lush rm <tool> --force # override the dirty-tree refusal
```

A generated stub also lazy-installs on first run if its `bin/lib/<tool>/main.sh` is missing —
`lush install` is both what a stub calls automatically and what you run by hand to prep a machine
or go offline deliberately.

### Navigation Engine

`system/shared/nav-engine.sh` — universal path resolver powering `tx`, `pw`, `yoink`, `yeet`, `wormhole`, `z`, `peek`, `edit`, `scav`.

**Flags**: `-f`/`--file` enables file resolution (default is directory-only), `--log` enables debug output.

**Nav Index Shorthand**:
```
h/  → $HOME/         H/  → /home/
w/  → $WORKSPACE/    t/  → $TOOLS/       c/  → $HOME/.config/
b/|bin/ → $HOME/bin/     d/  → $HOME/Downloads/   l/ → $HOME/.local/
sb/ → /usr/local/bin/   doc/ → $DOCUMENTS/    etc/ → /etc/
s/|serv/|ser/ → $SERVICES_DIR/
med/|pic/|vid/ → $MEDIA/
```

**Resolution Order**: nav index expansion → exact path → right-to-left fuzzy decomposition → glob matching with scoring → zoxide fallback.

**Using nav-engine in scripts**:
```bash
dest=$("$SYSDIR/shared/nav-engine.sh" "$1")          # directory resolution
dest=$("$SYSDIR/shared/nav-engine.sh" -f "$1")       # file-aware resolution
dest=$("$SYSDIR/shared/nav-engine.sh" --log "$1")    # with debug output
```

Remote bootstrapping: `yoink`/`yeet` pipe `nav-engine.sh` via stdin to SSH for remote path resolution.

### Cross-shell directory recency (zz)

`system/shared/z-history.sh` — `zz` jumps to the latest directory *any* shell moved to, so a
freshly-opened terminal can land where the last one left off. Sourced (not run) from `source.sh`,
since it has to `cd` the calling shell.

`z -` is deliberately left alone: everywhere in Unix `-` means this shell's own previous directory
(`cd -` is POSIX), and it is exact. `zz` is a different, fuzzier thing — last-writer-wins across N
terminals — so it gets its own token rather than overloading a precise one. `z --` was never an
option: zoxide already uses it for the POSIX end-of-options sense (`z -- <path>`).

Recording is a `PROMPT_COMMAND` hook rather than a hook inside `z()`, so `cd`, `tx`, `pushd` and
anything else that moves the shell are all captured by one path. Three rules make it work:

- **`$HOME` is never recorded** — otherwise a newly-opened terminal's own first prompt overwrites
  the target before you can jump to it, and the feature defeats itself.
- **`zz` skips `$PWD`** — after you `cd`, your own shell is the last writer, so a single-value
  store would make `zz` a no-op. Depth ≥ 2 is a requirement, not a nicety; history holds 10.
- **Deleted directories are skipped at read time**, degrading to the next entry instead of failing.

State lives in `/tmp/z-history-$USER` (same convention as `tx-undo-$USER`). `/tmp` is correct here:
after a reboot there are no other terminals whose position would be worth restoring.

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

`.N` subnet shorthand via `system/shared/net.sh` works across all SSH tools:
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
- **vibecheck**: Port scanning, process finding, hardware info, system metrics, disk usage

### Disk reclaim providers (vibecheck)

`vch disk` prints the filesystem header, the biggest consumers under `$HOME` (plus system roots),
and a reclaimable total. `vch disk PATH` scopes the consumer list to a subtree, and a path-shaped
bare argument (`vch .`, `vch w/lushrc`) is treated as a disk lookup — a bare word stays a process
search, so `vch firefox` never changes meaning based on the current directory.

`vch disk reclaim` advertises what it will run, confirms, then executes. **It never issues a delete
of its own.** Every command it runs comes from a provider in `bin/lib/vibecheck/reclaim/`, and each
provider is a black box answering three verbs:

```
detect   exit 0 if the owning tool exists on this machine
size     print reclaimable BYTES, as computed by the owning tool itself
plan     print  COMMAND \t CONSEQUENCE \t NEEDS_SUDO
```

**A provider may only exist when the owning tool accounts for its own reclaimable bytes and ships
its own command to free them.** That rule is what keeps this machine-independent — there is no
curated list of paths someone guessed were disposable, so there is nothing to rot. Locations that
would require a guess (`~/.cache`, the trash) deliberately have **no** provider: they appear as
sized rows in the consumers list and never as an action. Adding support for a new tool is one new
file in `reclaim/` and no edit anywhere else — `sample/reclaim.sh` globs the directory.

Both samplers cache to `/tmp/vch-disk-$USER` with a 24h expiry, and `disk reclaim` deletes that
directory after running so the next `vch disk` cannot report freed space as still reclaimable.
- **conf**: Quick access to config files
- **lush**: Self-management (`update`, `status`, `version`, `root`, `install`, `rm`, `list`)
- **gh-install** (`system/shared/gh-install.sh`): `gh_install <binary> <user/repo>` — lazy-installs GitHub-hosted binaries via the-satellite. Used by `tcpeek`, `netboop`, `dredge`, `dots`.

## Development Patterns

### Adding a New Command

1. Create `bin/newcmd` with `#!/usr/bin/env bash`, make executable
2. `reload` — symlink appears in `~/bin/` automatically
3. For system-wide (sudo) access: `lush root newcmd`
4. If it grows real internal seams, split it: move it to `bin/lib/newcmd/main.sh`, `reload` to
   auto-generate the `bin/newcmd` stub (see system/ vs bin/lib/ above)

### Adding a Library

- **System-wide** (shell-init dependency, used by multiple binaries): `system/shared/newlib.sh`, source via `source "$SYSDIR/shared/newlib.sh"`
- **Tool-specific, shared by that tool's own entrypoints**: `bin/lib/toolname/helper.sh` (no `main.sh` in that dir — it's a library, not a tool)
- **Command-specific, single tool**: same, under that tool's own `bin/lib/cmdname/`

Key system libs:
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
- **Status-line grammar** (emerging convention, currently `bigbrother`/`bb`, `cronotrigger`/`ctg`, `lsh`): list and confirmation output uses a leading ASCII mark instead of prose — `+ name` (added/enabled/reachable), dim `- name` (disabled/unreachable), dim strikethrough `x name` (removed). Color/strikethrough styling is TTY-only (`[[ -t 1 && -z "${NO_COLOR:-}" ]]`); the ASCII mark itself is always printed so piped/logged output stays greppable (`grep '^+'`). Each tool implements its own `<tool>_status_line mark name` helper (e.g. `bigbrother_status_line`, `cronotrigger_status_line`, `lsh_status_line`) rather than sharing one across tools, since each has its own module-loading boundary. When adding a new tool with enable/disable/add/remove semantics, follow this grammar instead of inventing new prose messages.

## Architecture Reference

### Reload Workflow

```
reload command
  ↓
source ~/.bashrc
  ↓
$SYSDIR/reload/reload.sh
  ├─ ensure-dirs.sh       (mkdir -p all workspace dirs)
  ├─ chmod +x             (bin/, TOOLS/bin/, bin/lib/*/main.sh, system/*/*)
  ├─ symlink-farm.sh
  │   ├─ cleanup broken symlinks
  │   ├─ sync_tool_stubs → generate bin/<name> for any new bin/lib/<name>/main.sh
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
| `modules/universal/paths.sh` | Everything | Defines all env vars incl. `$SYSDIR`, `$LIBDIR` |
| `system/shared/nav-engine.sh` | tx, pw, yoink, yeet, z, peek, edit, scav, wormhole | Path resolution engine |
| `system/shared/net.sh` | dock, yoink, yeet, evres, lsh, scav | LAN IP detection + `.N` shorthand |
| `system/shared/ssh-conn.sh` | yoink, yeet, dock | `parse_conn` → `CONN_*`, plus `conn_ssh`/`conn_ssh_pipe`/`conn_rsync` |
| `bin/lib/yeetyoink/remote.sh` | yoink, yeet | Remote path resolution + existence/tool probes |
| `bin/lib/yeetyoink/prompt.sh` | yoink, yeet | `confirm_block` transfer confirmation UI |
| `system/shared/spinner.sh` | dock, yoink | Terminal progress indicator |
| `system/shared/z-wrapper.sh` | `source.sh` (z function) | Enhanced zoxide wrapper |
| `system/shared/z-history.sh` | `source.sh` (zz function) | Cross-shell directory recency |
| `system/shared/gh-install.sh` | tcpeek, netboop, dredge, dots | Lazy GitHub binary installer |
| `system/reload/reload.sh` | `reload` alias, `lush` | Orchestrates config refresh |
| `system/reload/symlink-farm.sh` | `reload.sh` | Symlink maintenance + tool stub generation |
| `bin/lib/cronotrigger/main.sh` | `bin/cronotrigger` stub | Split-tool entrypoint (6 sourced modules) |
| `bin/lib/yeet/main.sh`, `bin/lib/yoink/main.sh` | their stubs | Twin binaries sharing `bin/lib/yeetyoink/` |
| `bin/lib/lsh/main.sh` | `bin/lsh`, `bin/ssh` stub/alias | Split-tool entrypoint; owns extensionless helpers (`mosh-client`, `ssh-askpass`, `latency`) |
| `bin/lib/vibecheck/sample/reclaim.sh` | `vch disk`, `vch disk reclaim` | Provider contract + aggregation |
| `bin/lib/vibecheck/reclaim/*.sh` | `sample/reclaim.sh` | One self-detecting provider per tool |
| `bin/hotline` | tmux | Async command launcher |
