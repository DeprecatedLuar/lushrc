#!/usr/bin/env bash
# Downloads rotation - keeps 3 reboots of history in .cache/downloads/{1,2,3}
# Called on login shells - only runs once per boot via /tmp flag

FLAG="/tmp/.lushrc_boot_cleanup"

if grep -q "downloads" "$FLAG" 2>/dev/null; then
    exit 0
fi

if [ -z "$DOWNLOADS_STAGE" ]; then
    source "${BASHRC:-$HOME/.config/lushrc}/modules/universal/paths.sh"
fi

STAGE="$DOWNLOADS_STAGE"
mkdir -p "$STAGE/1" "$STAGE/2" "$STAGE/3"
ln -sfn "$STAGE" "$DOWNLOADS/.previous"

# Skip rotation if Downloads has no real files (ignore .previous symlink)
shopt -s nullglob dotglob
files=("$DOWNLOADS"/*)
real_files=()
for f in "${files[@]}"; do
    [[ "$(basename "$f")" == ".previous" ]] && continue
    real_files+=("$f")
done
shopt -u dotglob
if [ ${#real_files[@]} -eq 0 ]; then
    echo "downloads" >> "$FLAG"
    exit 0
fi

# Shift: 2→3, 1→2
rm -rf "$STAGE/3"
mv "$STAGE/2" "$STAGE/3"
mv "$STAGE/1" "$STAGE/2"
mkdir -p "$STAGE/1"

# Archive current downloads
mv "${real_files[@]}" "$STAGE/1"/

echo "downloads" >> "$FLAG"
