#!/usr/bin/env bash
#
# 00-bootstrap.sh — from an empty directory to a patched, lunch-able tree.
#
# Usage:
#   ./bootstrap/00-bootstrap.sh ~/xt
#
# This is the single entry point. Everything it does is idempotent.
#
set -euo pipefail

TREE="${1:-$HOME/xt}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY="$(dirname "$SELF")"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
say "0. Preconditions"
# ---------------------------------------------------------------------------
for t in git curl python3; do
    command -v "$t" >/dev/null || die "missing $t"
done
git lfs version >/dev/null 2>&1 || die "git-lfs missing (repo init uses --git-lfs)"

avail_gb=$(df -BG --output=avail "$(dirname "$TREE")" | tail -1 | tr -dc '0-9')
say "   free space: ${avail_gb} GB (need >= 400 for a shallow sync)"
[[ "$avail_gb" -ge 400 ]] || die "not enough disk; a shallow A17 sync is ~230 GB"

mkdir -p "$TREE"
cd "$TREE"

# ---------------------------------------------------------------------------
say "1. repo init (Infinity X 4.2 / Android 17)"
# ---------------------------------------------------------------------------
if [[ -d .repo ]]; then
    say "   .repo exists — skipping init"
else
    repo init --no-repo-verify --git-lfs \
        -u https://github.com/ProjectInfinity-X/manifest \
        -b 17 \
        -g default,-mips,-darwin,-notdefault
fi

# ---------------------------------------------------------------------------
say "2. install our local manifest"
# ---------------------------------------------------------------------------
mkdir -p .repo/local_manifests
cp "$OVERLAY/manifest/xt-exynos9611.xml" .repo/local_manifests/
say "   installed xt-exynos9611.xml"

# ---------------------------------------------------------------------------
say "3. repo sync"
# ---------------------------------------------------------------------------
# -c / --current-branch keeps it to one branch per project. --force-sync makes
# retries recover from a half-finished previous attempt.
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync \
    -j"$(nproc)"

# ---------------------------------------------------------------------------
say "4. apply the four deltas"
# ---------------------------------------------------------------------------
bash "$OVERLAY/build/patch-trees.sh" "$TREE"

# ---------------------------------------------------------------------------
say "5. verify readiness"
# ---------------------------------------------------------------------------
source build/envsetup.sh
lunch xt_m31-userdebug || die "lunch xt_m31-userdebug failed — see docs/TROUBLESHOOTING.md"

say "Ready. Build with:"
printf '    cd %s && source build/envsetup.sh && lunch xt_m31-userdebug && m bacon\n\n' "$TREE"
