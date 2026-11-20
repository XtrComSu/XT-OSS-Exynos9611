#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# verify-product.sh — does the built product actually CONTAIN our stuff?
#
# WHY THIS EXISTS
# ---------------
# verify-release.sh checks the output dir for a zip, a boot.img, and the right
# build tags. None of that proves the Nothing layer is inside it. This checks the
# staged product tree: apps present as APKs, fonts staged onto the product
# partition, bootanimation in place, overlays installed.
#
# It exists because "the build succeeded" and "the ROM has our styling in it" are
# different claims, and only the second one matters.
#
# A TRAP WORTH DOCUMENTING (I fell into it)
# -----------------------------------------
# Looking for a PRODUCT_COPY_FILES entry in the ninja graph, the obvious files are
# out/soong/build.<product>*.ninja and out/combined-<product>.ninja. Both are wrong.
#   - out/combined-<product>.ninja is a 5-line STUB that only subninjas the others.
#   - PRODUCT_COPY_FILES rules live in out/build-<product>.ninja, ~1.6 GB.
# Grepping the stub returns 0 matches and looks exactly like "the fonts are missing
# from the build". They were not. Check the staged product tree instead — it is what
# actually ships, and it is cheap to read.
#
# Usage: build/verify-product.sh <out/target/product/<device>>
# Exit: 0 everything present, 1 something missing
#
set -uo pipefail

OUT="${1:-}"
[[ -n "$OUT" ]] || { printf 'usage: %s <out/target/product/device>\n' "$0" >&2; exit 1; }
[[ -d "$OUT" ]] || { printf 'no such dir: %s\n' "$OUT" >&2; exit 1; }

fail=0; warn=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mMISSING\033[0m %s\n' "$*"; fail=$((fail+1)); }
soft() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; warn=$((warn+1)); }

# Find a file anywhere under the staged partitions. Paths differ slightly between
# AOSP versions (system vs system/system), so search rather than hardcode.
find_one() {
    find "$OUT" -maxdepth 5 -name "$1" 2>/dev/null | head -1
}

printf '=== product contents: %s ===\n\n' "$OUT"

printf 'apps:\n'
for a in XtThemes XtWidgets XtStatus; do
    p=$(find_one "$a.apk")
    [[ -n "$p" ]] && ok "$a.apk  ($(stat -c%s "$p" | numfmt --to=iec 2>/dev/null || stat -c%s "$p") B)" \
                  || bad "$a.apk — the app will not be on the device"
done

printf '\ntheme overlays:\n'
for o in XtThemeNothing XtThemeNothingLight XtThemeMonet XtThemeStock; do
    p=$(find_one "$o.apk")
    [[ -n "$p" ]] && ok "$o.apk" || bad "$o.apk — that theme option will be absent"
done

printf '\ntype:\n'
for f in Doto-VariableFont.ttf Inter-VariableFont.ttf; do
    p=$(find_one "$f")
    [[ -n "$p" ]] && ok "$f" || bad "$f — body text falls back to Roboto"
done
p=$(find_one "fonts_customization.xml")
# Without this the .ttf files sit on the partition unregistered and do nothing.
[[ -n "$p" ]] && ok "fonts_customization.xml" || bad "fonts_customization.xml — fonts will NOT register"

printf '\nboot:\n'
p=$(find_one "bootanimation.zip")
if [[ -n "$p" ]]; then
    sz=$(stat -c%s "$p")
    # A tiny bootanimation.zip usually means an empty or truncated archive, which
    # shows a black screen for the whole boot rather than our animation.
    if (( sz < 10000 )); then
        bad "bootanimation.zip is only ${sz} B — likely empty, expect a black boot"
    else
        ok "bootanimation.zip ($(numfmt --to=iec "$sz" 2>/dev/null || echo "$sz") B)"
    fi
else
    bad "bootanimation.zip — stock animation will show"
fi

printf '\nbuild props:\n'
prop_files=()
for cand in "$OUT/product/etc/build.prop" "$OUT/product/build.prop" "$OUT/system/build.prop" "$OUT/vendor/build.prop"; do
    [[ -f "$cand" ]] && prop_files+=("$cand")
done
if (( ${#prop_files[@]} )); then
    for k in ro.xt.version ro.xt.codename ro.build.tags; do
        v=$(grep -h -m1 "^$k=" "${prop_files[@]}" 2>/dev/null | head -1 | cut -d= -f2-)
        [[ -n "$v" ]] && ok "$k=$v" || soft "$k not set"
    done
else
    soft "no build.prop found yet (build still running?)"
fi

# The GApps trim is the other thing that can silently not apply.
printf '\nGApps trim (should be absent):\n'
for m in Velvet GMS_Go Gboard LatinIMEGooglePrebuilt; do
    p=$(find_one "$m.apk")
    [[ -z "$p" ]] && ok "$m absent as intended" || soft "$m is present — check the allowlist"
done

printf '\n'
if (( fail )); then
    printf '\033[31mPRODUCT INCOMPLETE\033[0m — %d missing, %d warning(s).\n' "$fail" "$warn"
    exit 1
fi
printf '\033[32mPRODUCT COMPLETE\033[0m — %d warning(s).\n' "$warn"
exit 0
