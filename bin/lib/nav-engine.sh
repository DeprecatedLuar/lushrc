#!/usr/bin/env bash
# nav-engine - Universal navigation path resolver
# Resolves queries using nav indices, zoxide (optional), fuzzy search, and path expansion

# Parse flags
DEBUG=false
FILE_MODE=false
while [[ "$1" == -* ]]; do
    case "$1" in
        --dry-run) shift ;;  # nav-engine already just prints paths
        --log|--debug) DEBUG=true; shift ;;
        -f|--file) FILE_MODE=true; shift ;;
        *) shift ;;
    esac
done

query="$1"

# Debug helper - write directly to terminal (bypasses buffering and z-wrapper capture)
debug() {
    [[ "$DEBUG" == true ]] && printf "\033[2m[nav] %s\033[0m\n" "$*" > /dev/tty
}

# Show similar directories as suggestions
suggest_similar() {
    local base_dir="$1"
    local query="$2"

    [[ ! -d "$base_dir" ]] && return

    # Find directories containing the query (case-insensitive glob)
    local suggestions=()
    shopt -s nocaseglob nullglob
    local glob_matches=("$base_dir"/*"$query"*/)
    shopt -u nocaseglob nullglob

    for match in "${glob_matches[@]}"; do
        suggestions+=("${match%/}")  # Remove trailing slash
        suggestions[-1]="${suggestions[-1]##*/}"  # Keep only basename
    done

    # If no substring matches, show all directories as context
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        while IFS= read -r dir; do
            [[ -n "$dir" ]] && suggestions+=("$dir")
        done < <(ls -1 "$base_dir" 2>/dev/null | head -5)
        [[ ${#suggestions[@]} -gt 0 ]] && printf "  contents of %s: %s\n" "$base_dir" "${suggestions[*]}" >&2
    else
        printf "  did you mean: %s\n" "${suggestions[*]}" >&2
    fi
}

# Check if zoxide is available
HAS_ZOXIDE=false
command -v zoxide &>/dev/null && HAS_ZOXIDE=true

# Empty query or ~ = home directory
if [[ -z "$query" || "$query" == "~" ]]; then
    echo "$HOME"
    exit 0
fi

# Expand ~/path to $HOME/path
if [[ "$query" == "~/"* ]]; then
    query="$HOME/${query#\~/}"
fi

# Nav index expansion
expand_index() {
    case "$1" in
        w/*)   echo "$WORKSPACE/${1#w/}" ;;
        t/*)   echo "$TOOLS/${1#t/}" ;;
        f/*)   echo "$FOREIGN/${1#f/}" ;;
        h/*)   echo "$HOMEMADE/${1#h/}" ;;
        c/*)   echo "$HOME/.config/${1#c/}" ;;
        b/*)   echo "$HOME/bin/${1#b/}" ;;
        sb/*)  echo "/usr/local/bin/${1#sb/}" ;;
        lb/*)  echo "$HOME/.local/bin/${1#lb/}" ;;
        d/*)   echo "$HOME/Downloads/${1#d/}" ;;
        doc/*) echo "$DOCUMENTS/${1#doc/}" ;;
        pic/*) echo "${XDG_PICTURES_DIR:-$HOME/Pictures}/${1#pic/}" ;;
        vid/*) echo "${XDG_VIDEOS_DIR:-$HOME/Videos}/${1#vid/}" ;;
        l/*)   echo "$HOME/.local/${1#l/}" ;;
        etc/*) echo "/etc/${1#etc/}" ;;
        w)     echo "$WORKSPACE" ;;
        t)     echo "$TOOLS" ;;
        f)     echo "$FOREIGN" ;;
        h)     echo "$HOMEMADE" ;;
        c)     echo "$HOME/.config" ;;
        b)     echo "$HOME/bin" ;;
        sb)    echo "/usr/local/bin" ;;
        lb)    echo "$HOME/.local/bin" ;;
        d)     echo "$HOME/Downloads" ;;
        doc)   echo "$DOCUMENTS" ;;
        pic)   echo "${XDG_PICTURES_DIR:-$HOME/Pictures}" ;;
        vid)   echo "${XDG_VIDEOS_DIR:-$HOME/Videos}" ;;
        l)     echo "$HOME/.local" ;;
        etc)   echo "/etc" ;;
        *)     echo "$1" ;;
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

    if [[ -d "${exact_matches[0]}" ]] || { [[ "$FILE_MODE" == true ]] && [[ -e "${exact_matches[0]}" ]]; }; then
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

    if [[ -d "${target_matches[0]}" ]] || { [[ "$FILE_MODE" == true ]] && [[ -e "${target_matches[0]}" ]]; }; then
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

# Glob-based directory search (handles permissions better than find)
glob_search() {
    local base="$1" query="$2" max_depth="${3:-3}"
    shopt -s nocaseglob nullglob

    for ((d=1; d<=max_depth; d++)); do
        local pattern="$base"
        for ((i=1; i<d; i++)); do pattern+="/*"; done

        # Directory glob (always)
        local dir_pattern="${pattern}/*${query}*/"
        debug "  -> Glob depth $d: ${dir_pattern##$base/}"
        local results=($dir_pattern)

        # File glob (only in file mode)
        if [[ "$FILE_MODE" == true ]]; then
            local file_pattern="${pattern}/*${query}*"
            local file_results=($file_pattern)
            for f in "${file_results[@]}"; do
                [[ -f "$f" ]] && results+=("$f")
            done
        fi

        if [[ ${#results[@]} -gt 0 ]]; then
            shopt -u nocaseglob nullglob
            printf '%s\n' "${results[@]%/}"
            return 0
        fi
    done

    shopt -u nocaseglob nullglob
    return 1
}

# Find best match using scoring algorithm
# Scores by: depth (shallow better), length similarity, position, exact substring
find_best_match() {
    local search_base="$1"
    local query="$2"

    debug "find_best_match: searching in '$search_base' for '$query'"

    local matches=()

    # Try glob first (depths 1-3, handles permissions better)
    while IFS= read -r match; do
        matches+=("$match")
    done < <(glob_search "$search_base" "$query" 3)

    if [[ ${#matches[@]} -gt 0 ]]; then
        debug "  -> Glob found ${#matches[@]} matches"
    else
        # Glob failed - fall back to find for deeper searches
        debug "  -> Glob found nothing, trying find (depth 4-10)..."
        local find_type=(-type d)
        [[ "$FILE_MODE" == true ]] && find_type=(\( -type d -o -type f \))
        for depth in {4..10}; do
            debug "  -> Find depth $depth..."
            while IFS= read -r -d '' match; do
                matches+=("$match")
            done < <(find "$search_base" -maxdepth "$depth" -mindepth "$depth" "${find_type[@]}" -iname "*$query*" -print0 2>/dev/null)

            if [[ ${#matches[@]} -gt 0 ]]; then
                debug "  -> Found ${#matches[@]} candidates at depth $depth"
                break
            fi
        done
    fi

    debug "  -> Total: ${#matches[@]} candidates"

    # No matches
    if [[ ${#matches[@]} -eq 0 ]]; then
        debug "  -> No matches found for '$query' in '$search_base'"
        return 1
    fi

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
        debug "  '$test_path' not a directory, walking back..."
        test_path="${test_path%/*}"
        [[ -z "$test_path" ]] && test_path="/"
    done

    debug "Existing base: $test_path"

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

    # Failed - show helpful context
    echo "nav-engine: no match found for '$query'" >&2
    debug "  base resolved to: $test_path"
    debug "  failed to resolve suffix: $suffix"

    # Extract the first component that failed and suggest alternatives
    first_missing="${suffix%%/*}"
    suggest_similar "$test_path" "$first_missing"
    exit 1
fi

# Handle queries with path separators (nav indices, zoxide base + path suffix)
if [[ "$query" == */* ]]; then
    base_query="${query%%/*}"
    suffix="${query#*/}"

    # Try nav index expansion on base first
    base="$(expand_index "$base_query")"

    # If nav index didn't match, try zoxide or treat as literal path
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
    debug "Resolving '$suffix' from base '$base'"
    target=$(resolve_path_recursive "$base" "$suffix")

    if [[ -n "$target" ]]; then
        echo "$target"
        exit 0
    else
        echo "nav-engine: no match found for '$query'" >&2
        first_missing="${suffix%%/*}"
        suggest_similar "$base" "$first_missing"
        exit 1
    fi
fi

# Try current directory match (case-insensitive) for simple queries
local_find_type=(-type d)
[[ "$FILE_MODE" == true ]] && local_find_type=(\( -type d -o -type f \))
local_match=$(find . -maxdepth 1 "${local_find_type[@]}" -iname "$query" -print -quit 2>/dev/null)
if [[ -n "$local_match" ]]; then
    echo "$PWD/${local_match#./}"
    exit 0
fi

# Try nav index expansion for simple queries (no path separator)
expanded="$(expand_index "$query")"
if [[ "$expanded" != "$query" ]]; then
    echo "$expanded"
    exit 0
fi

# Try zoxide if available, otherwise fail gracefully
if [[ "$HAS_ZOXIDE" == true ]]; then
    debug "Trying zoxide for '$query'"
    target="$(zoxide query "$query" 2>/dev/null)"
    if [[ -n "$target" ]]; then
        echo "$target"
        exit 0
    else
        echo "nav-engine: no match found for '$query'" >&2
        # Show what's in current directory as context
        suggest_similar "$PWD" "$query"
        exit 1
    fi
else
    echo "nav-engine: cannot resolve '$query' (zoxide not installed, use nav indices or paths)" >&2
    suggest_similar "$PWD" "$query"
    exit 1
fi
