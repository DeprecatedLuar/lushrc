#!/usr/bin/env bash
# nav-engine - Universal navigation path resolver
# Resolves queries using TX indices, zoxide (optional), fuzzy search, and path expansion

# Parse flags
DEBUG=false
while [[ "$1" == --* ]]; do
    case "$1" in
        --dry-run) shift ;;  # nav-engine already just prints paths
        --log) DEBUG=true; shift ;;
        *) shift ;;
    esac
done

query="$1"

# Debug helper
debug() {
    [[ "$DEBUG" == true ]] && echo "[DEBUG] $*" >&2
}

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

# Recursive path resolution with case-insensitive fuzzy fallback
# Decomposes RIGHT-TO-LEFT: tries full path, strips from end until something exists
resolve_path_recursive() {
    local current_base="$1"
    local remaining_suffix="$2"

    debug "resolve_path_recursive: base='$current_base' suffix='$remaining_suffix'"

    # Base case: no more suffix to resolve
    if [[ -z "$remaining_suffix" ]]; then
        debug "  -> Base case, returning: $current_base"
        echo "$current_base"
        return 0
    fi

    # Try exact path first (case-insensitive via glob)
    shopt -s nocaseglob
    local exact_matches=("$current_base"/$remaining_suffix)
    shopt -u nocaseglob

    if [[ -d "${exact_matches[0]}" ]]; then
        debug "  -> Exact match found: ${exact_matches[0]}"
        echo "${exact_matches[0]}"
        return 0
    fi

    debug "  -> Exact match failed, decomposing..."

    # Exact failed - decompose by removing LAST component (right-to-left)
    local target="${remaining_suffix##*/}"      # Last component to find (docu)
    local parent_path="${remaining_suffix%/*}"  # Path without last component (home/tenshi)

    # Single component case (no more slashes)
    if [[ "$target" == "$parent_path" ]]; then
        # Fuzzy search with intelligent scoring
        local best_match
        best_match=$(find_best_match "$current_base" "$target")

        if [[ -n "$best_match" ]]; then
            echo "$best_match"
            return 0
        fi
        return 1
    fi

    # Multi-component: first resolve parent path, then find target within it
    local resolved_parent
    resolved_parent=$(resolve_path_recursive "$current_base" "$parent_path")

    if [[ -z "$resolved_parent" ]]; then
        # Couldn't resolve parent path
        return 1
    fi

    # Parent resolved - now try to find target within it
    # Try exact match first (case-insensitive)
    shopt -s nocaseglob
    local target_matches=("$resolved_parent"/$target)
    shopt -u nocaseglob

    if [[ -d "${target_matches[0]}" ]]; then
        echo "${target_matches[0]}"
        return 0
    fi

    # Exact failed - fuzzy search for target with intelligent scoring
    local best_match
    best_match=$(find_best_match "$resolved_parent" "$target")

    if [[ -n "$best_match" ]]; then
        echo "$best_match"
        return 0
    fi

    return 1
}

# Find best match using scoring algorithm
# Scores by: depth (shallow better), length similarity, position, exact substring
#
# KNOWN LIMITATION: Performance degrades on remote filesystems (SSHFS, NFS, CIFS)
# because find traverses directories over the network. Consider reducing maxdepth
# or detecting remote FS types (fuse.sshfs, nfs, cifs) and using shallower search.
# For now, use the tool directly on the remote server when working with remote paths.
find_best_match() {
    local search_base="$1"
    local query="$2"

    debug "find_best_match: searching in '$search_base' for '$query'"

    # Find all matches
    local matches=()
    while IFS= read -r -d '' match; do
        matches+=("$match")
    done < <(find "$search_base" -maxdepth 10 -type d -iname "*$query*" -print0 2>/dev/null)

    debug "  -> Found ${#matches[@]} candidates"

    # No matches
    [[ ${#matches[@]} -eq 0 ]] && return 1

    # Single match - easy
    if [[ ${#matches[@]} -eq 1 ]]; then
        debug "  -> Single match: ${matches[0]}"
        echo "${matches[0]}"
        return 0
    fi

    # Multiple matches - score them
    debug "  -> Scoring multiple matches..."
    local best_match=""
    local best_score=-999999
    local base_depth
    base_depth=$(echo "$search_base" | tr -cd '/' | wc -c)

    for match in "${matches[@]}"; do
        local dirname="${match##*/}"

        # Depth penalty (deeper = worse)
        local match_depth
        match_depth=$(echo "$match" | tr -cd '/' | wc -c)
        local depth=$((match_depth - base_depth))

        # Length difference (prefer similar length to query)
        local len_diff=$((${#dirname} - ${#query}))
        [[ $len_diff -lt 0 ]] && len_diff=$((-len_diff))

        # Position of query in dirname (prefer early position)
        local lower_dirname="${dirname,,}"
        local lower_query="${query,,}"
        local position=0
        if [[ "$lower_dirname" == *"$lower_query"* ]]; then
            local prefix="${lower_dirname%%$lower_query*}"
            position=${#prefix}
        fi

        # Exact substring bonus
        local exact_bonus=0
        [[ "$lower_dirname" == *"$lower_query"* ]] && exact_bonus=100

        # Calculate score (higher = better)
        local score=$((1000 - depth*100 - len_diff - position*10 + exact_bonus))

        debug "     [$score] $match (depth=$depth, len_diff=$len_diff, pos=$position)"

        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_match="$match"
        fi
    done

    debug "  -> Best match (score=$best_score): $best_match"

    echo "$best_match"
    return 0
}

# Handle absolute paths (starting with /)
if [[ "$query" == /* ]]; then
    debug "Absolute path detected: $query"

    # Edge case: query is just "/"
    if [[ "$query" == "/" ]]; then
        echo "/"
        exit 0
    fi

    # Find longest existing prefix by walking backwards from the full path
    test_path="$query"
    while [[ ! -d "$test_path" && "$test_path" != "/" ]]; do
        test_path="${test_path%/*}"
        [[ -z "$test_path" ]] && test_path="/"
    done

    debug "Last existing directory: $test_path"

    # Extract suffix to resolve
    if [[ "$test_path" == "/" ]]; then
        suffix="${query#/}"
    else
        suffix="${query#$test_path/}"
    fi

    debug "Suffix to resolve: $suffix"

    # If no suffix, the path already exists (we would have returned it earlier)
    if [[ -z "$suffix" ]]; then
        echo "$test_path"
        exit 0
    fi

    # Recursively resolve the remaining suffix from the existing base
    result=$(resolve_path_recursive "$test_path" "$suffix")

    if [[ -n "$result" ]]; then
        debug "Final result: $result"
        echo "$result"
        exit 0
    fi

    echo "nav-engine: no match found for '$query'" >&2
    exit 1
fi

# Handle queries with path separators (TX indices, zoxide base + path suffix)
if [[ "$query" == */* ]]; then
    base_query="${query%%/*}"
    suffix="${query#*/}"

    # Try TX index expansion on base first
    base="$(expand_index "$base_query")"

    # If TX index didn't match, try zoxide or treat as literal path
    if [[ "$base" == "$base_query" ]]; then
        # Never feed . or .. to zoxide - treat as literal relative paths
        if [[ "$base_query" == "." ]] || [[ "$base_query" == ".." ]]; then
            base="$base_query"
        elif [[ "$HAS_ZOXIDE" == true ]]; then
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

    # Use recursive resolution for the suffix
    target=$(resolve_path_recursive "$base" "$suffix")

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
