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

mkdir -p "$T/build"
cat > "$T/build/envsetup.sh" <<'EOS'
# Mirrors upstream lunch() closely enough for D5: the legacy form
# <product>-<variant> must be split BEFORE the product name is tested, which is
# what the real function does with  IFS="-" read -r product variant <<< "$1"
lunch() {
    local product variant
    local legacy=$(echo $1 | grep "-")
    if [[ $# -eq 1 && -n $legacy ]]; then
        IFS="-" read -r product variant <<< "$1"
    else
        product=$1
    fi
    if (echo -n $1 | grep -q -e "^infinity_") ; then
      INFINITY_BUILD=$(echo -n $product | sed -e 's/^infinity_//g')
    else
      INFINITY_BUILD=
    fi
    export INFINITY_BUILD
}
EOS

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
check "D3 pinned clang version" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_VERSION := r416183b' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"
check "D3 set explicit clang path" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_PATH := .*prebuilts/clang/kernel' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"
check "D3 defines BUILD_TOP" "1" \
      "$(grep -c '^BUILD_TOP := \$(abspath \.)$' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"

# ---- 2. idempotency -------------------------------------------------------
run >/dev/null
check "D2 not duplicated" "1" \
      "$(grep -c 'XT-OS overlay products' "$T/device/samsung/m31/AndroidProducts.mk" || true)"
check "D3 not duplicated" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_VERSION :=' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"
check "D3 clang path not duplicated" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_PATH :=' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"
check "D3 BUILD_TOP not duplicated" "1" \
      "$(grep -c '^BUILD_TOP :=' "$T/device/samsung/universal9611-common/BoardConfigCommon.mk" || true)"
check "D5 not duplicated" "1" \
      "$(grep -c 'XT-OS: INFINITY_BUILD for xt_' "$T/build/envsetup.sh" || true)"

# ---- 2b. migrate a tree patched by the OLD script (clang pin only) --------
# The first version of D3 appended only TARGET_KERNEL_CLANG_VERSION/PATH, which
# left BUILD_TOP unset and the kernel unbuildable. Such a tree must be upgraded
# in place, not left broken and not duplicated.
OLD_FIXTURE="$T/device/samsung/universal9611-common/BoardConfigCommon.mk"
python3 - "$OLD_FIXTURE" <<'PYEOF'
import sys
p = sys.argv[1]
t = open(p).read()
i = t.find("# XT-OS: BUILD_TOP is undefined on Infinity X")
if i != -1:
    open(p, "w").write(t[:i].rstrip("\n") + "\n")
open(p, "a").write(
    "\n# XT-OS: pin an era-appropriate clang for the 4.14 kernel\n"
    "TARGET_KERNEL_CLANG_VERSION := r416183b\n"
    "TARGET_KERNEL_CLANG_PATH := $(BUILD_TOP)/prebuilts/clang/kernel/linux-x86/clang-r416183b\n")
PYEOF
run >/dev/null
check "migration: BUILD_TOP added" "1" \
      "$(grep -c '^BUILD_TOP := \$(abspath \.)$' "$OLD_FIXTURE" || true)"
check "migration: old block replaced once" "1" \
      "$(grep -c 'TARGET_KERNEL_CLANG_VERSION :=' "$OLD_FIXTURE" || true)"
check "D5 added xt_ branch" "1" \
      "$(grep -c 'grep -q -e "\^xt_"' "$T/build/envsetup.sh" || true)"
check "D5 strips xt_ prefix" "1" \
      "$(grep -c "s/\^xt_//g" "$T/build/envsetup.sh" || true)"

# D5 must actually make INFINITY_BUILD non-empty for xt_m31
got=$( cd "$T" && bash -c '. build/envsetup.sh; lunch xt_m31-userdebug >/dev/null; echo "$INFINITY_BUILD"' )
check "D5 INFINITY_BUILD resolves for xt_m31" "m31" "$got"
got2=$( cd "$T" && bash -c '. build/envsetup.sh; lunch infinity_m31-userdebug >/dev/null; echo "$INFINITY_BUILD"' )
check "D5 upstream infinity_ still works" "m31" "$got2"

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
