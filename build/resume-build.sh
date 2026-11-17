#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# resume-build.sh — pick up an interrupted bring-up build without redoing work.
#
# WHY THIS EXISTS
# ---------------
# Long AOSP builds get interrupted: the machine is reclaimed, a session drops, a
# kernel OOM-kills clang. The instinct is to preserve `out/` somewhere safe. On the
# boxes we use that is the wrong move — there is no persistent volume, and copying
# ~17 GB of objects off-host costs more than it saves.
#
# The build is already resumable. Soong+siso track a dep log per output; re-running
# `m bacon` skips every target whose inputs are unchanged and continues from the
# frontier. On an interrupted 230k-target AOSP build that means a restart costs
# minutes of analysis, not hours of compilation.
#
# What actually needs protecting is not the objects but the *reason the build
# exists*: the tree state. So this script verifies the tree first — a resumed build
# against a drifted vendor/xt or a swapped kernel produces a hybrid that never
# existed in any branch, and it looks successful.
#
# Usage: build/resume-build.sh <tree-root> [product] [jobs]
#
set -uo pipefail

T="${1:-}"
[[ -n "$T" ]] || { printf 'usage: %s <tree-root> [product] [jobs]\n' "$0" >&2; exit 1; }
PRODUCT="${2:-m31}"
JOBS="${3:-$(nproc)}"
[[ -d "$T" ]] || { printf 'no such tree: %s\n' "$T" >&2; exit 1; }

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m    %s\033[0m\n' "$*"; }

cd "$T" || exit 1

say "0. what survived"
objs=$(find out -name '*.o' 2>/dev/null | wc -l)
printf '    compiled objects : %s\n' "$objs"
printf '    out/ size        : %s\n' "$(du -sh out 2>/dev/null | cut -f1)"
if [[ "$objs" -eq 0 ]]; then
    warn "no objects found — this will be a full cold build, not a resume"
fi

say "1. verify the tree is still the tree we meant to build"
# This is the part worth being strict about. Objects from the WRONG tree are worse
# than no objects: they link into an image that never matched any source state.
if [[ -x vendor/xt/build/check-tree-fresh.sh ]]; then
    if ! bash vendor/xt/build/check-tree-fresh.sh "$T"; then
        printf '\n\033[31mrefusing to resume\033[0m — fix the tree first:\n'
        printf '    bash vendor/xt/build/pull-overlay.sh %s\n' "$T"
        exit 1
    fi
else
    warn "no freshness gate found; proceeding unverified"
fi

say "2. kernel state (SUSFS must be present or the ROM is half-promised)"
K=kernel/samsung/universal9611
if [[ -f "$K/fs/susfs.c" ]]; then
    printf '    fs/susfs.c: %s bytes\n' "$(stat -c%s "$K/fs/susfs.c")"
else
    warn "fs/susfs.c missing — this kernel has no SUSFS"
fi
grep -q '^CONFIG_KSU_SUSFS=y' "$K/arch/arm64/configs/exynos9611-m31_defconfig" 2>/dev/null \
    && printf '    defconfig : CONFIG_KSU_SUSFS=y\n' \
    || warn "defconfig does not set CONFIG_KSU_SUSFS=y"

say "3. release keys (a test-keys build is not shippable)"
if [[ -f vendor/xt/keys/releasekey.pk8 ]]; then
    printf '    present — build will be signed\n'
else
    warn "no release keys; building with test-keys. Run build/gen-release-keys.sh first."
fi

say "4. resume"
source build/envsetup.sh
lunch "xt_${PRODUCT}-userdebug" || { printf 'lunch failed\n' >&2; exit 1; }
printf '    PRODUCT_DEFAULT_DEV_CERTIFICATE = %s\n' "$(get_build_var PRODUCT_DEFAULT_DEV_CERTIFICATE 2>/dev/null)"
printf '    module count = %s\n' "$(get_build_var PRODUCT_PACKAGES 2>/dev/null | wc -w)"

printf '\n    resuming with -j%s\n\n' "$JOBS"
m bacon -j"$JOBS"
rc=$?

say "5. result"
if [[ $rc -ne 0 ]]; then
    printf '\033[31mBUILD FAILED (rc=%s)\033[0m — objects are intact, so a re-run resumes here.\n' "$rc"
    exit $rc
fi
ls -la out/target/product/"$PRODUCT"/*.zip 2>/dev/null || warn "build returned 0 but produced no zip"
printf '\n\033[32mdone\033[0m — now gate it:\n'
printf '    vendor/xt/build/verify-release.sh out/target/product/%s --kernel-dir kernel/samsung/universal9611\n' "$PRODUCT"
printf '    vendor/xt/build/verify-product.sh out/target/product/%s\n' "$PRODUCT"
