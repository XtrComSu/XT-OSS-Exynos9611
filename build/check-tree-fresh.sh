#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# check-tree-fresh.sh — is the tree about to be built actually the repo you edited?
#
# WHY THIS EXISTS
# ---------------
# A four-hour build was lost to this. vendor/xt is a clone of the overlay repo, and
# `repo sync` does not fast-forward an existing clone to the tip of main — it leaves
# whatever commit was checked out. So the build compiled an overlay that predated
# three apps, two fonts, a boot animation and the fixed theme overlays, and produced
# a stock-looking ROM.
#
# Nothing in the build log hinted at it. The missing apps were not named in
# xt-assets.mk, they were absent from it, so there was no "module not found" error
# to catch. A finished, green, bootstrap-passing build would have shipped the wrong
# thing.
#
# Run this before any long build. It compares the tree against this repo and fails
# loudly on drift.
#
# Usage: build/check-tree-fresh.sh <tree-root>
# Exit: 0 fresh, 1 stale or missing
#
set -uo pipefail

TREE="${1:-}"
[[ -n "$TREE" ]] || { printf 'usage: %s <tree-root>\n' "$0" >&2; exit 1; }
[[ -d "$TREE" ]] || { printf 'no such tree: %s\n' "$TREE" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$TREE/vendor/xt"

fail=0
ok()  { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mSTALE\033[0m %s\n' "$*"; fail=$((fail+1)); }

printf '=== tree freshness: %s ===\n' "$TREE"

if [[ ! -d "$V/.git" ]]; then
    bad "vendor/xt is not a git clone — the overlay is missing entirely"
    printf '\nfatal: nothing to build against\n' >&2
    exit 1
fi

here=$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo "?")
there=$(git -C "$V" rev-parse HEAD 2>/dev/null || echo "?")
printf '  overlay repo : %s\n  tree vendor/xt: %s\n' "${here:0:10}" "${there:0:10}"

if [[ "$here" == "$there" ]]; then
    ok "vendor/xt matches the overlay repo exactly"
else
    bad "vendor/xt is on a different commit than this repo"
    printf '         fix: bash build/pull-overlay.sh %s\n' "$TREE"
fi

# Independent of git state: are the things we expect actually there? A commit can
# match while a file is untracked (generated, or added but not committed).
printf '\n  assets and apps:\n'
check() {
    if [[ -e "$V/$1" ]]; then ok "$1"; else bad "$1"; fi
}
check apps/XtThemes/Android.bp
check apps/XtWidgets/Android.bp
check apps/XtStatus/Android.bp
check fonts/Doto-VariableFont.ttf
check fonts/Inter-VariableFont.ttf
check fonts/fonts_customization.xml
check artwork/bootanimation.zip
check build/verify-overlays.py
check build/verify-gapps.py
check build/verify-release.sh

# The generated fragment is gitignored, so it can be absent on a clean clone and
# must be regenerated rather than reported as a stale git state.
if [[ -s "$V/config/xt-assets.mk" ]]; then
    ok "config/xt-assets.mk (non-empty)"
else
    bad "config/xt-assets.mk is empty or missing — fonts/artwork will NOT ship
         fix: bash $V/build/gen-assets.sh"
fi

printf '\n'
if (( fail )); then
    printf '\033[31mSTALE TREE\033[0m — %d problem(s). Do not start a build.\n' "$fail"
    exit 1
fi
printf '\033[32mFRESH\033[0m — safe to build.\n'
exit 0
