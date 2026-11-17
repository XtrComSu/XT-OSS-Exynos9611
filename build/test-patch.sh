#!/usr/bin/env bash
#
# test-patch.sh — prove patch-trees.sh works, without touching a real tree.
#
# Builds a fixture that mirrors the upstream layout closely enough to exercise
# D1, D2, D3, then asserts: applies cleanly, is idempotent, and fails loudly on
# residual vendor/lineage references.
#
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY="$(dirname "$SELF")"
T="$(mktemp -d /tmp/xt-fixture.XXXXXX)"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
check() { # check <label> <expected> <actual>
    # NOTE: pass=$((pass+1)), not ((pass++)). Under `set -e`, a post-increment
    # from 0 evaluates to 0, i.e. false, and kills the script on the first PASS.
    if [[ "$2" == "$3" ]]; then printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1))
    else printf '  \033[31mFAIL\033[0m %s (want %q got %q)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# ---- fixture ---------------------------------------------------------------
mkdir -p "$T/.repo" "$T/device/samsung/m31" "$T/device/samsung/universal9611-common" \
         "$T/vendor/infinity/config"
touch "$T/vendor/infinity/config/common_full_phone.mk" \
      "$T/vendor/infinity/config/BoardConfigReservedSize.mk"

printf '$(call inherit-product, vendor/lineage/config/common_full_phone.mk)\nPRODUCT_NAME := lineage_m31\n' \
    > "$T/device/samsung/m31/lineage_m31.mk"
printf 'PRODUCT_MAKEFILES := \\\n    $(LOCAL_DIR)/lineage_m31.mk\n' \
    > "$T/device/samsung/m31/AndroidProducts.mk"
printf 'TARGET_KERNEL_NO_GCC := true\ninclude vendor/lineage/config/BoardConfigReservedSize.mk\n' \
    > "$T/device/samsung/universal9611-common/BoardConfigCommon.mk"

run() { bash "$OVERLAY/build/patch-trees.sh" "$T" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }

# ---- 1. clean apply --------------------------------------------------------
run >/dev/null
check "D1 rewrote BoardConfigCommon.mk" "1" \
      "$(grep -c 'vendor/infinity/config/BoardConfigReservedSize.mk' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"
check "D1 rewrote lineage_m31.mk" "1" \
      "$(grep -c 'vendor/infinity/config/common_full_phone.mk' "$T/device/samsung/m31/lineage_m31.mk" || true)"
check "no vendor/lineage left" "0" \
      "$(grep -r 'vendor/lineage' "$T/device" 2>/dev/null | wc -l | tr -d ' ')"
check "D2 registered our product" "1" \
      "$(grep -c 'vendor/xt/products/xt_m31.mk' "$T/device/samsung/m31/AndroidProducts.mk" || true)"
check "D3 pinned clang" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_VERSION := r416183b' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"

# ---- 2. idempotency -------------------------------------------------------
run >/dev/null
check "D2 not duplicated" "1" \
      "$(grep -c 'XT-OS overlay products' "$T/device/samsung/m31/AndroidProducts.mk" || true)"
check "D3 not duplicated" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_VERSION' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"

# ---- 3. residual reference must be fatal ----------------------------------
printf 'prefix=vendor/lineage/config\n' > "$T/device/samsung/m31/some.conf"
set +e; run >/dev/null; rc=$?; set -e
check "residual reference exits 1" "1" "$rc"

# ---- 4. and recoverable ---------------------------------------------------
rm -f "$T/device/samsung/m31/some.conf"
set +e; run >/dev/null; rc=$?; set -e
check "clean tree exits 0" "0" "$rc"

# ---- summary --------------------------------------------------------------
printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
