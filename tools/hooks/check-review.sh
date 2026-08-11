#!/usr/bin/env bash
#
# Block a push that has not passed pz-review.
#
# MECHANISM: pz-review writes ".pz-review-stamp" with the HEAD commit hash
# when a review passes. This script checks that stamp matches the current HEAD.
# If it doesn't match (or doesn't exist), the push is blocked.
#
# INSTALL: tools/hooks/install.sh symlinks this into .git/hooks/pre-push-check-review
#
# RATIONALE: the orchestrator (OpenCode/Claude) is the only actor that runs
# pz-review. A human doing git push from the command line cannot accidentally
# skip it because the stamp won't be there. A push from the orchestrator after
# a review pass works because the stamp was written in the same session.
#
# The stamp is git-ignored so it never reaches the remote.
set -u

ROOT="$(git rev-parse --show-toplevel)"
STAMP="$ROOT/.pz-review-stamp"
HEAD="$(git rev-parse HEAD)"

if [ ! -f "$STAMP" ]; then
    cat >&2 <<'MSG'

pre-push: pz-review STAMP MISSING

No .pz-review-stamp found. This means no pz-review has been run for
the current tree. Run:

    pz-review (via the orchestrator)

before pushing. Every push must carry a review stamp matching HEAD.

MSG
    exit 1
fi

STAMPED="$(head -1 "$STAMP")"
if [ "$STAMPED" != "$HEAD" ]; then
    cat >&2 <<MSG

pre-push: pz-review STAMP STALE

  Review was run on: ${STAMPED:0:8}
  Current HEAD is:   ${HEAD:0:8}

These differ. The tree has changed since the last pz-review.
Run pz-review again on the current HEAD before pushing.

MSG
    exit 1
fi

echo "pre-push: review stamp matches HEAD (${STAMPED:0:8})"
exit 0
