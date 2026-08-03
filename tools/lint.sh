#!/bin/bash
# Lint everything we author. Two checks, both catching failures that otherwise
# only surface at runtime on the other machine:
#   1. Lua syntax     -- PZ is Lua 5.1, luajit parses it without the game.
#   2. Item ids       -- a fabricated Base.Foo fails SILENTLY in game. It is the
#                        single most expensive class of bug in this project.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VANILLA="$ROOT/pzserver/media/scripts"
fail=0

mapfile -t OURS < <(find "$ROOT/mods" -name "*.lua" 2>/dev/null)

echo "== lua syntax =="
if [ ${#OURS[@]} -eq 0 ]; then
    echo "  (no lua files yet)"
else
    for f in "${OURS[@]}"; do
        if luajit -bl "$f" >/dev/null 2>&1; then
            echo "  ok   ${f#$ROOT/}"
        else
            echo "  FAIL ${f#$ROOT/}"
            luajit -bl "$f" 2>&1 | head -3 | sed 's/^/       /'
            fail=1
        fi
    done
fi

echo "== item ids =="
if [ ! -d "$VANILLA" ]; then
    echo "  SKIP - pzserver/ not installed, cannot verify ids"
else
    # Index every item/vehicle/recipe name vanilla and the vendored mods define.
    index=$(mktemp)
    grep -rhoE "^[[:space:]]*(item|vehicle|craftRecipe)[[:space:]]+[A-Za-z0-9_]+" \
        "$VANILLA" "$ROOT/vendor" 2>/dev/null | awk '{print $NF}' | sort -u > "$index"
    echo "  indexed $(wc -l < "$index") definitions"

    # Every Base.X we wrote, from lua and from the bandits/scripts data files.
    used=$(grep -rhoE "\bBase\.[A-Za-z0-9_]+" "$ROOT/mods" 2>/dev/null \
           | sed 's/^Base\.//' | sort -u)
    missing=0
    for id in $used; do
        grep -qxF "$id" "$index" || { echo "  UNKNOWN Base.$id"; missing=1; fail=1; }
    done
    [ $missing -eq 0 ] && echo "  all referenced ids resolve"
    rm -f "$index"
fi

[ $fail -eq 0 ] && echo "== clean ==" || echo "== FAILED =="
exit $fail
