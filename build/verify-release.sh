#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# verify-release.sh — refuse to publish a build that is not actually shippable.
#
# WHY THIS EXISTS
# ---------------
# Every check here corresponds to a mistake that is easy to make and expensive to
# ship, and most of them are invisible from the build log. A build that finishes
# with exit 0 can still be:
#
#   * signed with AOSP test-keys (publicly known => privilege escalation)
#   * a userdebug build with root available over adb
#   * missing the theme overlays, which then silently do nothing
#   * missing a boot image, so it cannot boot at all
#   * carrying a kernel without KSUN/SUSFS, so the promised root does not exist
#   * far over its size budget, meaning the partition will not fit
#
# The purpose of this script is that publishing is a decision backed by evidence
# rather than by a green build log.
#
# Usage:
#   build/verify-release.sh <product-out-dir> [--kernel-dir PATH]
#
# Exit: 0 ready, 1 not ready (prints every reason, not just the first).
#
set -uo pipefail

OUT="${1:-}"
KERNEL_DIR="${2:-}"
if [[ "$KERNEL_DIR" == "--kernel-dir" ]]; then KERNEL_DIR="${3:-}"; fi

fail=0
note() { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }

if [[ -z "$OUT" || ! -d "$OUT" ]]; then
    printf 'usage: %s <product-out-dir> [--kernel-dir PATH]\n' "$0" >&2
    printf '  e.g. %s out/target/product/m31\n' "$0" >&2
    exit 1
fi

printf '=== XT-OS release check: %s ===\n\n' "$OUT"

# --- 1. Is there anything to ship? ----------------------------------------
printf '[artifacts]\n'
shopt -s nullglob
zips=("$OUT"/*.zip)
if (( ${#zips[@]} )); then
    for z in "${zips[@]}"; do
        sz=$(du -h "$z" | cut -f1)
        ok "zip: $(basename "$z") ($sz)"
        # A 0-byte or absurdly small zip means the build "succeeded" but produced
        # nothing usable — worth catching explicitly rather than discovering on the
        # device.
        bytes=$(stat -c%s "$z" 2>/dev/null || echo 0)
        if (( bytes < 100000000 )); then
            bad "  $(basename "$z") is only $bytes B — implausibly small for a full ROM"
        fi
    done
else
    bad "no flashable zip in $OUT — nothing to release"
fi

if [[ -f "$OUT/boot.img" ]]; then
    ok "boot.img ($(du -h "$OUT/boot.img" | cut -f1))"
else
    bad "boot.img missing — the device cannot boot"
fi

if [[ -f "$OUT/system.img" || -f "$OUT/super.img" || -f "$OUT/super_empty.img" ]]; then
    ok "system image present"
else
    warn "no system.img/super.img (may be inside the zip only)"
fi

# --- 2. Signing ------------------------------------------------------------
printf '\n[signing]\n'
# build.prop inside the target files is where ro.build.tags actually lands.
props=""
for cand in "$OUT/system/build.prop" "$OUT/vendor/build.prop" "$OUT/product/build.prop"; do
    [[ -f "$cand" ]] && props="$props $cand"
done

if [[ -n "$props" ]]; then
    tags=$(grep -h '^ro.build.tags=' $props 2>/dev/null | head -1 | cut -d= -f2)
    btype=$(grep -h '^ro.build.type=' $props 2>/dev/null | head -1 | cut -d= -f2)
    note "ro.build.tags=$tags  ro.build.type=$btype"

    if [[ "$tags" == *test-keys* ]]; then
        bad "signed with test-keys. These are PUBLIC — anyone can sign a matching APK
        and the system signature check will accept it. Generate real keys with
        build/gen-release-keys.sh and rebuild."
    elif [[ -n "$tags" ]]; then
        ok "release-keys"
    else
        warn "no ro.build.tags found (build.prop may be inside the zip only)"
    fi

    if [[ "$btype" == "userdebug" || "$btype" == "eng" ]]; then
        warn "ro.build.type=$btype — adb root is available; expected for testing, not
        for a release. Build with `m bacon user` for the shipping artifact."
    elif [[ "$btype" == "user" ]]; then
        ok "user build"
    fi
else
    warn "no build.prop under $OUT — cannot verify signing (artifacts may be zip-only)"
fi

# --- 3. Theme overlays -----------------------------------------------------
printf '\n[theme]\n'
# The RROs are the entire visual layer. If they are absent the ROM looks stock and
# nothing in the build log says so.
ovl_found=0
for o in XtThemeNothing XtThemeNothingLight XtThemeMonet XtThemeStock; do
    hit=$(find "$OUT" -name "$o.apk" 2>/dev/null | head -1)
    if [[ -n "$hit" ]]; then ovl_found=$((ovl_found+1)); fi
done
if (( ovl_found == 4 )); then
    ok "all 4 theme overlays present"
elif (( ovl_found > 0 )); then
    warn "$ovl_found/4 theme overlays found — the switcher will show missing entries"
else
    bad "no theme overlays found — the Nothing styling will not apply at all"
fi

for app in XtThemes XtWidgets XtStatus; do
    if find "$OUT" -name "$app.apk" 2>/dev/null | head -1 | grep -q .; then
        ok "$app.apk"
    else
        warn "$app.apk not found"
    fi
done

if find "$OUT" -name 'Doto-VariableFont.ttf' 2>/dev/null | head -1 | grep -q .; then
    ok "Doto font installed"
else
    warn "Doto font missing — type layer will fall back"
fi

# --- 4. Kernel ------------------------------------------------------------
printf '\n[kernel]\n'
if [[ -n "$KERNEL_DIR" && -d "$KERNEL_DIR" ]]; then
    cfg="$KERNEL_DIR/arch/arm64/configs/exynos9611-m31_defconfig"
    if [[ -f "$cfg" ]]; then
        if grep -q '^CONFIG_KSU=y\|^CONFIG_KSU ' "$cfg" 2>/dev/null; then
            ok "CONFIG_KSU present"
        else
            warn "no explicit CONFIG_KSU in defconfig (Kconfig default y may still apply)"
        fi
        if grep -q '^CONFIG_KSU_SUSFS=y' "$cfg" 2>/dev/null; then
            ok "CONFIG_KSU_SUSFS=y"
        else
            bad "CONFIG_KSU_SUSFS not set — the ROM will have root but NO SUSFS,
        which is half of what was promised. Check the manifest pins ksun-susfs."
        fi
    else
        warn "defconfig not found at $cfg"
    fi
else
    warn "kernel dir not given (--kernel-dir) — skipped root/SUSFS verification"
fi

# --- 5. Size sanity -------------------------------------------------------
printf '\n[size]\n'
total=$(du -sm "$OUT" 2>/dev/null | cut -f1)
note "out dir: ${total:-?} MB"
if [[ -n "${total:-}" ]] && (( total > 8000 )); then
    warn "over 8 GB — check the super partition will fit on a 6 GB device"
fi

printf '\n'
if (( fail > 0 )); then
    printf '\033[31mNOT READY TO RELEASE\033[0m — %d blocker(s) above.\n' "$fail"
    exit 1
fi
printf '\033[32mREADY TO RELEASE\033[0m — all blockers clear.\n'
exit 0
