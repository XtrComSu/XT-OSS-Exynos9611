#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# pull-overlay.sh — force vendor/xt to this repo's HEAD, then regenerate assets.
#
# The specific failure this prevents: `repo sync` does not fast-forward an existing
# clone of vendor/xt, so a rebuild silently uses an old overlay. A 4h build was lost
# to exactly that.
#
# Uses reset --hard rather than pull because vendor/xt is a build input, not a
# working copy — local edits there are a mistake worth discarding loudly, and a
# merge conflict mid-build is worse than losing an edit.
#
# Usage: build/pull-overlay.sh <tree-root>
#
set -euo pipefail

TREE="${1:-}"
[[ -n "$TREE" ]] || { printf 'usage: %s <tree-root>\n' "$0" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$TREE/vendor/xt"

say() { printf '==> %s\n' "$*"; }

[[ -d "$V/.git" ]] || { printf 'FATAL: %s is not a git clone\n' "$V" >&2; exit 1; }

# The manifest clones vendor/xt with a remote named `xtk`, not `origin`. Resolve
# whichever exists instead of assuming, which is what broke an earlier attempt.
remote=$(git -C "$V" remote | head -1)
[[ -n "$remote" ]] || { printf 'FATAL: vendor/xt has no git remote\n' >&2; exit 1; }

# Prefer the local repo as the source of truth when it is a clone of the same
# project — it may be ahead of the pushed branch, and building what is on disk is
# less surprising than building what was last pushed.
want=$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo "")
say "remote: $remote   target: ${want:0:10}"

if [[ -n "$want" ]] && git -C "$V" cat-file -e "$want" 2>/dev/null; then
    say "commit already present locally; resetting to it"
    git -C "$V" reset --hard "$want" --quiet
else
    branch=$(git -C "$HERE" branch --show-current 2>/dev/null || echo main)
    say "fetching $remote/$branch"
    git -C "$V" fetch --quiet "$remote" "$branch"
    git -C "$V" reset --hard FETCH_HEAD --quiet
fi

say "vendor/xt now at $(git -C "$V" rev-parse --short HEAD)"

# The asset fragment is generated and gitignored, so resetting does not restore it.
if [[ -x "$V/build/gen-assets.sh" ]]; then
    bash "$V/build/gen-assets.sh"
fi

say "done"
