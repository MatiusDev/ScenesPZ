#!/bin/bash
# Copy mods into ~/Zomboid/mods for the headless smoke test.
# Symlinks CANNOT be used: PZ resolves a symlinked mod dir to its absolute target and
# then re-appends it to the mods dir, producing paths like
#   ~/Zomboid/mods/home/matiusdev/zomboid/mods/bandits/42.20/media/scripts/zs_items.txt
# mod.info is still found, so the mod "loads" while every script silently fails.
set -e
W="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Zomboid/mods"
mkdir -p "$DEST"
for src in "$W"/mods/*/Contents/mods/*/ "$W"/vendor/*/mods/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"
    rm -rf "${DEST:?}/$name"
    cp -r "$src" "$DEST/$name"
    echo "synced $name"
done
