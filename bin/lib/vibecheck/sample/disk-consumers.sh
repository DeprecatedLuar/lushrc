#!/usr/bin/env bash
# disk-consumers.sh - biggest space consumers under a scope, cached
#
# Walking a large home directory touches every inode, which takes long enough
# that an uncached `vch disk` would stop being worth typing. Results are cached
# and expire on their own, so the cache never has to be thought about: within a
# session it is instant, a day later it is fresh again. Whatever frees space is
# expected to delete the cache directory rather than wait for the expiry.
#
# Output: BYTES \t PATH, largest first.
# Usage: disk-consumers.sh [--rescan] [PATH]

CACHE_DIR="${TMPDIR:-/tmp}/vch-disk-$USER"
CACHE_PREFIX=scan
CACHE_TTL_SECONDS=86400
SCAN_DEPTH=1
SCAN_LIMIT=12
# Directories outside $HOME that routinely dominate a root filesystem. Each is
# reported as a single total: they are not yours to reorganise, so a breakdown
# would be noise. Absent or other-filesystem entries drop out silently.
SYSTEM_ROOTS=(/nix /var /usr /opt /srv)

rescan=false
scope=""
for arg in "$@"; do
    case "$arg" in
        --rescan) rescan=true ;;
        -*)
            printf 'disk-consumers: unknown option %s\n' "$arg" >&2
            exit 2
            ;;
        *) scope="$arg" ;;
    esac
done

scoped=true
if [[ -z "$scope" ]]; then
    scope="$HOME"
    scoped=false
fi

[[ -d "$scope" ]] || {
    printf 'disk-consumers: not a directory: %s\n' "$scope" >&2
    exit 1
}

scope="$(cd -- "$scope" && pwd)"
cache_file="$CACHE_DIR/$CACHE_PREFIX${scope//\//_}"

scan() {
    # -x keeps each walk inside one filesystem; -d1 lists the scope's children,
    # and the scope's own total, which is dropped below.
    du -xb --max-depth="$SCAN_DEPTH" "$scope" 2>/dev/null \
        | awk -F'\t' -v scope="$scope" '$2 != scope'

    $scoped && return 0

    local root
    for root in "${SYSTEM_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        case "$root" in "$scope"/*|"$scope") continue ;; esac
        du -xb --max-depth=0 "$root" 2>/dev/null
    done
}

cache_expired() {
    local written
    written=$(stat -c %Y "$cache_file" 2>/dev/null) || return 0
    (( $(date +%s) - written >= CACHE_TTL_SECONDS ))
}

write_cache() {
    mkdir -p "$CACHE_DIR" || return 1
    scan | sort -k1,1nr | head -n "$SCAN_LIMIT" > "$cache_file"
}

if $rescan || [[ ! -s "$cache_file" ]] || cache_expired; then
    write_cache || exit 1
fi

cat "$cache_file"
