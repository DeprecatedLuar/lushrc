#!/usr/bin/env bash
# z-wrapper - Enhanced zoxide using nav-engine

# Check for dry-run flag
if [[ "$1" == "-q" || "$1" == "--dry-run" ]]; then
    shift
    target="$($LIBDIR/nav-engine.sh "$1" 2>&1)"
    if [[ $? -eq 0 ]]; then
        echo "$target"
    else
        echo "$target" >&2
        return 1
    fi
    return
fi

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

# Resolve path using nav-engine
target="$($LIBDIR/nav-engine.sh "$1" 2>&1)"

# Check if nav-engine succeeded
if [[ $? -eq 0 ]]; then
    cd "$target"
else
    # Print nav-engine's error message
    echo "$target" >&2
    return 1
fi
