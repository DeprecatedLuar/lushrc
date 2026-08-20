#!/usr/bin/env bash
# z-history - cross-shell directory recency; powers zz
#
# zoxide ranks by frecency and exposes no recency ordering (its db keeps
# last_accessed, but `zoxide query` can only sort by score). This tracks
# "where did any shell most recently go" separately, so a fresh terminal
# can land where the last one left off.
#
# `z -` stays what it is everywhere in Unix: this shell's own OLDPWD.
# `zz` is the global, last-writer-wins jump — deliberately a different
# token, because it is a fuzzier thing than `-` has ever meant.

Z_HISTORY_FILE="${TMPDIR:-/tmp}/z-history-$USER"
Z_HISTORY_DEPTH=10

# Prompt hook: record $PWD, newest first, deduped and trimmed.
# Hooked to the prompt rather than to z() so that cd, tx, pushd and anything
# else that moves the shell are all captured by the same path.
z_history_record() {
    # Only on actual movement - keeps idle prompts and `ls` from rewriting.
    [[ "$PWD" == "${_Z_HISTORY_LAST:-}" ]] && return 0
    _Z_HISTORY_LAST="$PWD"

    # $HOME is where every fresh terminal starts. Recording it would let a
    # newly-opened shell clobber the target before you could jump to it.
    [[ "$PWD" == "$HOME" ]] && return 0

    local tmp
    tmp="$(mktemp "$Z_HISTORY_FILE.XXXXXX" 2>/dev/null)" || return 0
    {
        printf '%s\n' "$PWD"
        grep -vxF "$PWD" "$Z_HISTORY_FILE" 2>/dev/null | head -n "$((Z_HISTORY_DEPTH - 1))"
    } >"$tmp" 2>/dev/null
    mv -f "$tmp" "$Z_HISTORY_FILE" 2>/dev/null || rm -f "$tmp"
}

# Print the most recent recorded directory that is neither $PWD nor stale.
# Skipping $PWD is what makes a single value insufficient: after you cd
# somewhere, your own shell is the last writer, so depth 1 would be a no-op.
z_history_last() {
    [[ -r "$Z_HISTORY_FILE" ]] || return 1
    local dir
    while IFS= read -r dir; do
        [[ -n "$dir" && "$dir" != "$PWD" && -d "$dir" ]] || continue
        printf '%s\n' "$dir"
        return 0
    done <"$Z_HISTORY_FILE"
    return 1
}

# Jump to wherever any shell most recently went.
zz() {
    local dir
    if ! dir="$(z_history_last)"; then
        echo "zz: no recent directory recorded" >&2
        return 1
    fi
    cd "$dir"
}

# Install the hook, matching zoxide's own idempotent idiom.
if [[ ${PROMPT_COMMAND:=} != *'z_history_record'* ]]; then
    PROMPT_COMMAND="z_history_record;${PROMPT_COMMAND#;}"
fi
