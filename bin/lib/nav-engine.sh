#!/usr/bin/env bash
# nav-engine - Universal navigation path resolver
# Resolves queries using TX indices, zoxide (optional), fuzzy search, and path expansion

# Strip --dry-run flag if present (nav-engine already just prints paths)
[[ "$1" == "--dry-run" ]] && shift

query="$1"

# Check if zoxide is available
HAS_ZOXIDE=false
command -v zoxide &>/dev/null && HAS_ZOXIDE=true

# Empty query = home directory
if [[ -z "$query" ]]; then
    echo "$HOME"
    exit 0
fi

# TX index expansion
expand_index() {
    case "$1" in
        w/*)  echo "$WORKSPACE/${1#w/}" ;;
        t/*)  echo "$TOOLS/${1#t/}" ;;
        f/*)  echo "$FOREIGN/${1#f/}" ;;
        h/*)  echo "$HOMEMADE/${1#h/}" ;;
        c/*)  echo "$HOME/.config/${1#c/}" ;;
        b/*)  echo "$HOME/bin/${1#b/}" ;;
        sb/*) echo "/usr/local/bin/${1#sb/}" ;;
        lb/*) echo "$HOME/.local/bin/${1#lb/}" ;;
        d/*)  echo "$HOME/Downloads/${1#d/}" ;;
        w)    echo "$WORKSPACE" ;;
        t)    echo "$TOOLS" ;;
        f)    echo "$FOREIGN" ;;
        h)    echo "$HOMEMADE" ;;
        c)    echo "$HOME/.config" ;;
        b)    echo "$HOME/bin" ;;
        sb)   echo "/usr/local/bin" ;;
        lb)   echo "$HOME/.local/bin" ;;
        d)    echo "$HOME/Downloads" ;;
        *)    echo "$1" ;;
    esac
}

# If it's an existing path, return as-is
if [[ -e "$query" ]]; then
    echo "$query"
    exit 0
fi

# Handle queries with path separators (TX indices, zoxide base + path suffix)
if [[ "$query" == */* ]]; then
    base_query="${query%%/*}"
    suffix="${query#*/}"

    # Try TX index expansion on base first
    base="$(expand_index "$base_query")"

    # If TX index didn't match, try zoxide or treat as literal path
    if [[ "$base" == "$base_query" ]]; then
        if [[ "$HAS_ZOXIDE" == true ]]; then
            base="$(zoxide query "$base_query" 2>/dev/null)"
            if [[ -z "$base" ]]; then
                echo "nav-engine: no match found for '$base_query'" >&2
                exit 1
            fi
        else
            # No zoxide - treat base_query as literal path
            if [[ ! -d "$base_query" ]]; then
                echo "nav-engine: directory not found '$base_query' (zoxide not installed)" >&2
                exit 1
            fi
            base="$base_query"
        fi
    fi

    # Try exact path first
    if [[ -d "$base/$suffix" ]]; then
        echo "$base/$suffix"
        exit 0
    fi

    # Exact path failed - fuzzy search for last component
    search_name="${suffix##*/}"
    target=$(find "$base" -type d -iname "*$search_name*" -print -quit 2>/dev/null)

    if [[ -n "$target" ]]; then
        echo "$target"
        exit 0
    else
        echo "nav-engine: no match found for '$query'" >&2
        exit 1
    fi
fi

# Try TX index expansion for simple queries (no path separator)
expanded="$(expand_index "$query")"
if [[ "$expanded" != "$query" ]]; then
    echo "$expanded"
    exit 0
fi

# Try zoxide if available, otherwise fail gracefully
if [[ "$HAS_ZOXIDE" == true ]]; then
    target="$(zoxide query "$query" 2>/dev/null)"
    if [[ -n "$target" ]]; then
        echo "$target"
        exit 0
    else
        echo "nav-engine: no match found for '$query'" >&2
        exit 1
    fi
else
    echo "nav-engine: cannot resolve '$query' (zoxide not installed, use TX indices or paths)" >&2
    exit 1
fi
