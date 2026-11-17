#!/bin/bash
# Produce a fallback boot.img from the previous KSUN branch, WITHOUT disturbing the
# main build. Run this only AFTER the main build has produced its boot.img.
#
# Why a script and not a worktree: AOSP's kernel build reads the kernel source at
# <tree>/kernel/samsung/universal9611 and writes to a single KERNEL_OBJ dir. A
# separate git worktree would not change where the build looks, so the only way to
# build the other branch's boot image is to swap the source, build, then swap back.
# Sequencing it after the main build is what keeps them from colliding.
set -uo pipefail

T="${1:-}"
[[ -n "$T" ]] || { printf 'usage: %s <tree-root> [product]\n' "$0" >&2; exit 1; }
PRODUCT="${2:-m31}"
[[ -d "$T" ]] || { printf 'no such tree: %s\n' "$T" >&2; exit 1; }

say() { printf '\n==> %s\n' "$*"; }
K=$T/kernel/samsung/universal9611
OUT=$T/out/target/product/$PRODUCT
KOBJ=$OUT/obj/KERNEL_OBJ
SAVE="$T/out/boot-fallback"
mkdir -p "$SAVE"

cd "$T" || exit 1

# 1. Preserve the primary boot image before touching anything.
if [ -f "$OUT/boot.img" ]; then
    cp "$OUT/boot.img" "$SAVE/boot-susfs.img"
    sha256sum "$SAVE/boot-susfs.img"
else
    echo "FATAL: no boot.img to preserve — build first (m bacon)"
    exit 1
fi

# 2. Fetch the previous branch and record where we came from.
cd "$K" || exit 1
ORIG=$(git rev-parse HEAD)
echo "primary kernel: $ORIG"
git fetch xtk lineage-24.0-KSUN || exit 1
git reset --hard FETCH_HEAD
git log --oneline -1
# This branch has NO SUSFS — confirm, so the artifact is honestly labelled.
grep -q 'CONFIG_KSU_SUSFS=y' arch/arm64/configs/exynos9611-m31_defconfig \
    && echo "NOTE: branch unexpectedly HAS susfs" \
    || echo "confirmed: this branch has no SUSFS (this is the fallback, not the release)"

# 3. Kernel objects are not ninja-tracked per file, so a stale dir silently reuses
#    the other branch's objects. Must clear.
rm -rf "$KOBJ"

# 4. Build ONLY the boot image — not a full OTA.
cd "$T" || exit 1
source build/envsetup.sh
lunch xt_${PRODUCT}-userdebug || exit 1
m bootimage -j"$(nproc)" || { echo "FALLBACK BUILD FAILED"; exit 1; }

if [ -f "$OUT/boot.img" ]; then
    cp "$OUT/boot.img" "$SAVE/boot-nosusfs.img"
    sha256sum "$SAVE/boot-nosusfs.img"
    ls -la "$SAVE"
fi

# 5. Restore the primary kernel source so the tree is left as it was.
cd "$K" || exit 1
git reset --hard "$ORIG"
git log --oneline -1
rm -rf "$KOBJ"

echo "=== FALLBACK DONE ==="
ls -la "$SAVE"
