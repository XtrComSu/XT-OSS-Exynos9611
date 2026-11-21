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
say "   free space: ${avail_gb} GB (need >= 350 for a shallow sync)"
[[ "$avail_gb" -ge 350 ]] || die "not enough disk; a shallow A17 sync is ~230 GB"

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
say "4. apply the deltas"
# ---------------------------------------------------------------------------
bash "$OVERLAY/build/patch-trees.sh" "$TREE"

# ---------------------------------------------------------------------------
say "5. refresh vendor/xt to the overlay repo's HEAD"
#
# WHY THIS STEP EXISTS
# --------------------
# vendor/xt is a clone of this overlay repo, and `repo sync` only updates it to
# whatever commit it already has checked out — it does not fast-forward an
# existing clone to the tip of `main`. So a second bootstrap run (or a re-run
# after new commits) silently keeps building the OLD overlay.
#
# That is not hypothetical. A 4-hour build here ran against a vendor/xt that
# predated the three apps, both fonts, the boot animation, and the fixed theme
# overlays. It would have produced a stock-looking ROM, and nothing in the build
# log would have said so: the missing apps were absent from the -include'd
# xt-assets.mk rather than named in it, so there was no "module not found" to
# catch. The only symptom would have been a finished zip with no Nothing styling
# in it.
#
# So: always fast-forward vendor/xt to the overlay's HEAD before building.
# ---------------------------------------------------------------------------
if [[ -d "$TREE/vendor/xt/.git" ]]; then
    xt_head=$(git -C "$OVERLAY" rev-parse HEAD 2>/dev/null || echo "?")
    say "   overlay HEAD: ${xt_head:0:10}"
    # The remote may be named `xtk` rather than `origin` depending on how the
    # manifest cloned it, so resolve whichever exists instead of assuming.
    branch=$(git -C "$TREE/vendor/xt" branch --show-current 2>/dev/null || echo main)
    if git -C "$TREE/vendor/xt" fetch --quiet "$(git -C "$TREE/vendor/xt" remote | head -1)" "$branch" 2>/dev/null; then
        git -C "$TREE/vendor/xt" reset --hard FETCH_HEAD --quiet
        say "   vendor/xt now at: $(git -C "$TREE/vendor/xt" rev-parse --short HEAD)"
    else
        say "   WARNING: could not refresh vendor/xt; building whatever is checked out"
    fi
else
    say "   vendor/xt missing — did repo sync fail?"
fi

# ---------------------------------------------------------------------------
say "6. regenerate the asset fragment"
#
# config/xt-assets.mk is generated and gitignored, so a fresh clone has none. It
# is -include'd by xt-common.mk, which means a missing fragment is silently
# skipped: fonts and artwork would just not ship. Regenerating here closes that.
# ---------------------------------------------------------------------------
if [[ -x "$TREE/vendor/xt/build/gen-assets.sh" ]]; then
    bash "$TREE/vendor/xt/build/gen-assets.sh" || say "   (gen-assets.sh reported problems)"
fi

# ---------------------------------------------------------------------------
say "7. verify readiness"
# ---------------------------------------------------------------------------
source build/envsetup.sh
lunch xt_m31-userdebug || die "lunch xt_m31-userdebug failed — see docs/TROUBLESHOOTING.md"

say "Ready. Build with:"
printf '    cd %s && source build/envsetup.sh && lunch xt_m31-userdebug && m bacon\n\n' "$TREE"
printf 'Then gate the output before publishing:\n'
printf '    vendor/xt/build/verify-release.sh out/target/product/m31 --kernel-dir kernel/samsung/universal9611\n\n'
