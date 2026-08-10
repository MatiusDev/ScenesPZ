#!/usr/bin/env bash
#
# Point git at tools/hooks/ instead of copying files into .git/hooks/.
#
# `core.hooksPath` is a git config setting, so the hooks live in the repository, are versioned
# with everything else, and arrive on the gaming PC with a plain `git pull`. Copying into
# .git/hooks/ would mean the Windows machine silently has no gate -- which is the machine where
# a bad push actually costs a play session.

set -eu

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

chmod +x tools/hooks/pre-push
git config core.hooksPath tools/hooks

echo "hooks installed: core.hooksPath -> tools/hooks"
echo
git config --get core.hooksPath
ls -l tools/hooks/pre-push
