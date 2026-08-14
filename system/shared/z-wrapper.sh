#!/usr/bin/env bash
# z-wrapper - Enhanced zoxide using nav-engine

# Parse flags to pass through to nav-engine
flags=()
dry_run=false

while [[ "$1" == --* || "$1" == "-q" ]]; do
    case "$1" in
        -q|--dry-run)
            dry_run=true
            shift
            ;;
        --log|--debug)
            flags+=("$1")
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# No args = go home
if [[ $# -eq 0 ]]; then
    cd "$HOME"
    return
fi

# Handle z - (return to previous directory)
if [[ "$1" == "-" ]]; then
    cd -
    return
fi

# Resolve path using nav-engine (suppress its error output)
target="$($LIBDIR/shared/nav-engine.sh "${flags[@]}" "$1" 2>/dev/null)"

# Check if nav-engine succeeded
if [[ $? -eq 0 ]]; then
    if [[ "$dry_run" == true ]]; then
        # Dry run - just print the path
        echo "$target"
    else
        # Normal mode - cd to the path
        cd "$target"
    fi
else
    # Simple error message
    echo "$1 not found" >&2
    return 1
fi
