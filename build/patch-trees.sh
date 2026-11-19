#!/usr/bin/env bash
#
# patch-trees.sh — apply the four XT deltas to freshly synced trees.
#
# Idempotent: safe to run after every `repo sync`. Every change is a precise
# textual substitution with a verification step, so a failed patch shouts rather
# than silently producing a broken build.
#
# Deltas (see docs/DELTAS.md):
#   D1  vendor/lineage -> vendor/infinity        (Infinity X has no vendor/lineage)
#   D2  register xt_<device>.mk in AndroidProducts.mk
#   D3  kernel clang pin + explicit clang PATH   (4.14 cannot use A17's default clang)
#   D4  copy our product + config into the tree
#
set -euo pipefail

TREE="${1:-$PWD}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY="$(dirname "$SELF")"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m  %s\n' "$*"; }
warn() { printf '    \033[33mwarn\033[0m %s\n' "$*"; }
die()  { printf '    \033[31mFATAL\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$TREE/.repo" ]] || die "$TREE does not look like a repo tree (no .repo)"
cd "$TREE"

DEVICES=(m31 m31s f41 m21 a51)

# ---------------------------------------------------------------------------
say "D1: vendor/lineage -> vendor/infinity"
# ---------------------------------------------------------------------------
mapfile -t hits < <(grep -rl 'vendor/lineage' \
    device/samsung vendor/samsung 2>/dev/null || true)

if [[ ${#hits[@]} -eq 0 ]]; then
    ok "nothing to patch"
else
    for f in "${hits[@]}"; do
        case "$f" in
            *.mk|*.bp|*.sh) ;;
            *) warn "skipping non-makefile $f"; continue ;;
        esac
        # Guard: the replacement target must exist, or we swap one broken include
        # for another. Both verified present in Infinity X @ branch 17.
        if [[ ! -f vendor/infinity/config/common_full_phone.mk ]] \
        && [[ ! -f vendor/infinity/config/BoardConfigReservedSize.mk ]]; then
            warn "vendor/infinity not synced yet — run repo sync first"
        fi
        sed -i 's|vendor/lineage|vendor/infinity|g' "$f"
        ok "patched $f"
    done
fi

if grep -rq 'vendor/lineage' device/samsung vendor/samsung 2>/dev/null; then
    die "vendor/lineage still referenced after D1"
fi
ok "verified: zero vendor/lineage references remain"

# ---------------------------------------------------------------------------
say "D2: register xt_<device>.mk in AndroidProducts.mk"
# ---------------------------------------------------------------------------
for d in "${DEVICES[@]}"; do
    apm="device/samsung/$d/AndroidProducts.mk"
    [[ -f "$apm" ]] || { warn "$apm absent (device not synced) — skip"; continue; }

    marker="# --- XT-OS overlay products ---"
    if grep -qF "$marker" "$apm"; then
        ok "$d already registered"
        continue
    fi

    cat >> "$apm" <<EOF

$marker
# PRODUCT_MAKEFILES entries are resolved relative to the top of the tree, so this
# is a root-relative path. Our product files stay in vendor/xt/products rather
# than being copied into the device tree, which keeps this delta to one block.
PRODUCT_MAKEFILES += \\
    vendor/xt/products/xt_$d.mk
EOF
    ok "registered xt_$d.mk"
done

# ---------------------------------------------------------------------------
say "D3: kernel clang pin (4.14 vs A17 toolchain)"
# ---------------------------------------------------------------------------
# Two facts, both verified by reading the synced tree on 2026-11-17:
#
#   1. vendor/infinity/config/BoardConfigKernel.mk sets
#          KERNEL_MAKE_FLAGS += LLVM=1 LLVM_IAS=1
#      unconditionally. That is FINE for this kernel: the universal9611
#      Makefile (4.14.357) has LLVM support backported and honours
#      `LLVM_IAS ?= 1` with a `-no-integrated-as` branch at Makefile:559.
#      So no override is needed — an earlier draft of this script wrongly
#      planned to disable IAS.
#
#   2. BoardConfigKernel.mk resolves the clang directory as
#          TARGET_KERNEL_CLANG_PATH ?= $(BUILD_TOP)/prebuilts/clang/host/$(HOST_PREBUILT_TAG)/$(KERNEL_CLANG_VERSION)
#      but the 4.14-era prebuilt in the Infinity X manifest lives under
#      prebuilts/clang/KERNEL/linux-x86/clang-r416183b. Setting only the
#      version therefore points at a directory that does not exist, and the
#      kernel build fails with a missing-compiler error. Both variables must
#      be set.
#
bcc="device/samsung/universal9611-common/BoardConfigCommon.mk"
if [[ -f "$bcc" ]]; then
    marker="# XT-OS: BUILD_TOP is undefined on Infinity X — restore it"
    legacy="# XT-OS: pin an era-appropriate clang for the 4.14 kernel"

    # Migration: an earlier version of this script appended only the clang pin.
    # That block is ours, it sits at EOF, and it is now superseded — so drop
    # everything from the old marker to the end and re-append the current block.
    if grep -qF "$legacy" "$bcc" && ! grep -qF "$marker" "$bcc"; then
        warn "found superseded D3 block — replacing it"
        python3 - "$bcc" "$legacy" <<'PY'
import sys
path, marker = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines(True)
for i, l in enumerate(lines):
    if marker in l:
        open(path, "w").write("".join(lines[:i]).rstrip("\n") + "\n")
        break
PY
    fi

    if grep -qF "$marker" "$bcc"; then
        ok "BUILD_TOP + clang pin already present"
    else
        cat >> "$bcc" <<'EOF'

# ---------------------------------------------------------------------------
# XT-OS: BUILD_TOP is undefined on Infinity X — restore it
# ---------------------------------------------------------------------------
# This is an upstream bug, not a device quirk. Verified on Infinity X (branch
# 17, AOSP android-17.0.0_r1): `grep -rn 'BUILD_TOP *:='` over the whole tree
# returns nothing. It is *used* in at least:
#
#   vendor/infinity/config/BoardConfigKernel.mk:93   TARGET_KERNEL_CLANG_PATH ?= $(BUILD_TOP)/prebuilts/...
#   vendor/infinity/config/BoardConfigKernel.mk:145  TOOLS_PATH_OVERRIDE += PATH=$(BUILD_TOP)/prebuilts/...
#   vendor/infinity/build/tasks/kernel.mk:162        KERNEL_MAKE_CMD := $(BUILD_TOP)/prebuilts/build-tools/.../make
#   vendor/infinity/build/tasks/kernel.mk:282,297    ... -C $(BUILD_TOP)/$(KERNEL_SRC) ...
#
# With BUILD_TOP empty, `m bacon` fails at the kernel step, and it fails
# confusingly: PATH entries silently become absolute paths like
# /prebuilts/clang/kernel/... which do not exist, so the error looks like a
# missing toolchain rather than an unset variable. Confirmed on the build host:
# `get_build_var TARGET_KERNEL_CLANG_PATH` returned
# "/prebuilts/clang/kernel/linux-x86/clang-r416183b" and
# `get_build_var KERNEL_MAKE_CMD` returned empty.
#
# kati runs make with its working directory at the tree root, so `$(abspath .)`
# is the correct top. Guarded with `ifeq` so that if upstream ever defines
# BUILD_TOP this becomes a no-op instead of fighting them.
ifeq ($(BUILD_TOP),)
BUILD_TOP := $(abspath .)
endif

# ---------------------------------------------------------------------------
# XT-OS: pin an era-appropriate clang for the 4.14 kernel
# ---------------------------------------------------------------------------
# The kernel is Linux 4.14.357. Infinity X's default is
# $(LLVM_AOSP_PREBUILTS_VERSION), which on Android 17 is far too new.
# clang-r416183b is a clang-12-era toolchain that 4.14 kernels build with,
# and it is ALREADY in the Infinity X manifest (snippets/lineage.xml), so
# this costs no extra download.
TARGET_KERNEL_CLANG_VERSION := r416183b

# The PATH must be set explicitly. BoardConfigKernel.mk defaults it to
# prebuilts/clang/host/<tag>/clang-<version>, but this prebuilt is shipped
# in prebuilts/clang/kernel/linux-x86/. Setting only the version above
# yields a nonexistent compiler directory.
#
# NOTE: no `LLVM_IAS=0` override here, deliberately. A 4.14 kernel would
# normally need -no-integrated-as, but universal9611 has LLVM backported: its
# top-level Makefile:558 has `LLVM_IAS ?= 1` with an ifeq branch that adds
# -no-integrated-as when set to 0. So Infinity X's unconditional
# `LLVM=1 LLVM_IAS=1` is correct for this kernel.
TARGET_KERNEL_CLANG_PATH := $(BUILD_TOP)/prebuilts/clang/kernel/linux-x86/clang-r416183b
EOF
        ok "restored BUILD_TOP + pinned clang r416183b and its path"
    fi

    # Verify the pinned compiler actually exists in this tree.
    cb="prebuilts/clang/kernel/linux-x86/clang-r416183b/bin/clang"
    if [[ -x "$cb" ]]; then
        ok "compiler present: $cb"
    else
        warn "compiler NOT found at $cb — sync may be incomplete"
    fi

    # Verify BUILD_TOP is now defined. A silent empty value here is the failure
    # mode this delta exists to prevent, so assert it rather than trusting the
    # append above.
    if grep -q '^BUILD_TOP := \$(abspath \.)$' "$bcc"; then
        ok "BUILD_TOP is defined (kernel.mk needs it)"
    else
        die "BUILD_TOP definition missing from $bcc"
    fi
else
    warn "$bcc absent — skip clang pin"
fi

# ---------------------------------------------------------------------------
say "D4: verify our overlay is reachable from the tree"
# ---------------------------------------------------------------------------
if [[ -f vendor/xt/config/xt-common.mk ]]; then
    ok "vendor/xt/config/xt-common.mk present"
else
    warn "vendor/xt not synced — add XT-OSS-Exynos9611 to your manifest"
fi

for d in "${DEVICES[@]}"; do
    if [[ -f "vendor/xt/products/xt_$d.mk" ]]; then
        ok "vendor/xt/products/xt_$d.mk present"
    fi
done

# ---------------------------------------------------------------------------
say "D5: make INFINITY_BUILD resolve for xt_* products"
# ---------------------------------------------------------------------------
# THE ROOT CAUSE of the kernel build failing, found only by running a real build.
#
# build/envsetup.sh, in the lunch() function, derives INFINITY_BUILD from the
# product name — but only if the name starts with "infinity_":
#
#     if (echo -n $1 | grep -q -e "^infinity_") ; then
#       INFINITY_BUILD=$(echo -n $product | sed -e 's/^infinity_//g')
#     else
#       INFINITY_BUILD=
#     fi
#
# Our products are xt_m31, xt_m31s, … so INFINITY_BUILD becomes empty. And
# build/make/core/config.mk:501 gates the entire Infinity config chain on it:
#
#     ifneq ($(INFINITY_BUILD),)
#     include vendor/infinity/config/BoardConfigLineage.mk
#     endif
#
# Empty INFINITY_BUILD therefore means BoardConfigLineage.mk never runs —
# and with it BoardConfigKernel.mk, which is what defines KERNEL_MAKE_CMD,
# KERNEL_BUILD_OUT_PREFIX, TARGET_KERNEL_CLANG_PATH and the whole
# TARGET_KERNEL_* surface. That is why:
#
#     $ get_build_var KERNEL_MAKE_CMD            -> (empty)
#     $ get_build_var KERNEL_BUILD_OUT_PREFIX    -> (empty)
#     $ get_build_var TARGET_KERNEL_CLANG_PATH   -> /prebuilts/... (BUILD_TOP empty)
#
# and why Soong then failed with
#     module "generated_kernel_includes": unknown variable '$(KERNEL_BUILD_OUT_PREFIX)'
#
# Fix: teach lunch() that xt_* is also one of our products, stripping the xt_
# prefix so INFINITY_BUILD holds the bare device name (m31), exactly as it does
# for infinity_m31. This is a two-line addition to the condition, done with a
# precise substitution so an upstream change makes this delta fail loudly
# rather than silently corrupting the function.
#
es="build/envsetup.sh"
if [[ -f "$es" ]]; then
    if grep -qF 'XT-OS: INFINITY_BUILD for xt_* products' "$es"; then
        ok "INFINITY_BUILD already accepts xt_*"
    else
        python3 - "$es" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()

anchor = (
    '    if (echo -n $1 | grep -q -e "^infinity_") ; then\n'
    '      INFINITY_BUILD=$(echo -n $product | sed -e \'s/^infinity_//g\')\n'
    '    else\n'
    '      INFINITY_BUILD=\n'
    '    fi\n'
)

replacement = (
    '    # XT-OS: INFINITY_BUILD for xt_* products\n'
    '    #\n'
    '    # Upstream only sets INFINITY_BUILD when the product name starts with\n'
    '    # "infinity_", and build/make/core/config.mk gates the entire\n'
    '    # vendor/infinity config chain on it being non-empty. Our products are\n'
    '    # xt_*, so without this the kernel configuration (BoardConfigKernel.mk:\n'
    '    # KERNEL_MAKE_CMD, KERNEL_BUILD_OUT_PREFIX, TARGET_KERNEL_*) is never\n'
    '    # loaded and the Soong kernel-header modules fail. Strip xt_ so the\n'
    '    # value is the bare device name, matching infinity_<device> behaviour.\n'
    '    if (echo -n $1 | grep -q -e "^infinity_") ; then\n'
    '      INFINITY_BUILD=$(echo -n $product | sed -e \'s/^infinity_//g\')\n'
    '    elif (echo -n $1 | grep -q -e "^xt_") ; then\n'
    '      INFINITY_BUILD=$(echo -n $product | sed -e \'s/^xt_//g\')\n'
    '    else\n'
    '      INFINITY_BUILD=\n'
    '    fi\n'
)

if anchor not in src:
    sys.exit(
        "D5: anchor not found in build/envsetup.sh — upstream changed the "
        "lunch() product-name logic. Inspect it manually:\n"
        "  grep -n 'infinity_' build/envsetup.sh"
    )

open(path, "w").write(src.replace(anchor, replacement, 1))
PY
        ok "lunch() now sets INFINITY_BUILD for xt_* products"
    fi

    if grep -q 'xt_' "$es" && grep -q 'INFINITY_BUILD' "$es"; then
        ok "verified: INFINITY_BUILD has an xt_ branch"
    else
        die "D5 verification failed in $es"
    fi
else
    warn "$es absent — cannot patch INFINITY_BUILD"
fi

# ---------------------------------------------------------------------------
say "D6: SDV lifecycle_manager host variant (A17 soong analysis abort)"
# ---------------------------------------------------------------------------
# Android 17's soong analyses EVERY Android.bp in the tree before honouring the
# product, so a module we never ship can still stop the build. Here
# system/software_defined_vehicle/lifecycle_management imports
# "google.sdv.identity-V2" while declaring host_supported: true, but the module
# it imports (hardware/sdv/interfaces/.../service_discovery) sets
# host_supported: false via sdv_sd_aidl_defaults. Soong resolves AIDL imports
# per-variant, so the host variant of identity genuinely does not exist and
# analysis dies with "Import does not exist: google.sdv.identity".
#
# SDV is automotive — an SM-M315F phone never builds it. Aligning the importer to
# device-only is the minimal, honest fix: it changes no device behaviour and does
# not fake a missing module. Verified by re-running soong analysis after patching.
#
LM="system/software_defined_vehicle/lifecycle_management/aidl/Android.bp"
if [[ -f "$LM" ]]; then
    if grep -q 'host_supported: true' "$LM"; then
        sed -i '0,/host_supported: true/s//host_supported: false/' "$LM"
        ok "set host_supported: false in lifecycle_manager (device-only)"
    elif grep -q 'host_supported: false' "$LM"; then
        ok "already device-only"
    else
        # No explicit flag: insert one so the aidl_interface stops claiming host.
        sed -i '0,/aidl_interface {/s//aidl_interface {\n    host_supported: false,/' "$LM"
        ok "inserted host_supported: false in lifecycle_manager"
    fi
    if grep -q 'host_supported: false' "$LM"; then
        ok "verified: lifecycle_manager is device-only"
    else
        die "D6 verification failed in $LM"
    fi
else
    warn "$LM absent — SDV tree not synced; nothing to patch"
fi

# ---------------------------------------------------------------------------
say "D7: align device-tree vendor.prop with XT efficiency props"
# ---------------------------------------------------------------------------
# AOSP's build/make/tools/post_process_props.py:118 aborts when one key is
# assigned twice with DIFFERENT values ("error: found duplicate sysprop
# assignments"). Identical duplicates are deduped silently, which is why most of
# our overrides coexist with the device tree unnoticed — but two do not:
#
#   ro.surface_flinger.supports_background_blur   ours 0   device tree 1
#   debug.sf.auto_latch_unsignaled                ours 1   device tree 0
#
# Dropping our overrides would silence the error and lose the point: both are
# RAM/GPU savings on M31-class hardware (Mali-G72 MP3). So the device tree's copy
# is rewritten to our value and our overrides for those two keys are removed, so
# exactly one file states each key. sed is anchored on the full key + value so an
# upstream value change makes this delta fail loudly instead of silently no-oping.
#
VPROP_DEV="device/samsung/universal9611-common/properties/vendor.prop"
if [[ -f "$VPROP_DEV" ]]; then
    if grep -q '^ro\.surface_flinger\.supports_background_blur=1$' "$VPROP_DEV"; then
        sed -i 's|^ro\.surface_flinger\.supports_background_blur=1$|ro.surface_flinger.supports_background_blur=0|' "$VPROP_DEV"
        ok "blur disabled in device vendor.prop (was 1)"
    elif grep -q '^ro\.surface_flinger\.supports_background_blur=0$' "$VPROP_DEV"; then
        ok "blur already disabled"
    else
        warn "blur key absent or unexpected value — inspect $VPROP_DEV"
    fi

    if grep -q '^debug\.sf\.auto_latch_unsignaled=0$' "$VPROP_DEV"; then
        sed -i 's|^debug\.sf\.auto_latch_unsignaled=0$|debug.sf.auto_latch_unsignaled=1|' "$VPROP_DEV"
        ok "auto_latch_unsignaled=1 in device vendor.prop (was 0)"
    elif grep -q '^debug\.sf\.auto_latch_unsignaled=1$' "$VPROP_DEV"; then
        ok "auto_latch_unsignaled already 1"
    else
        warn "auto_latch key absent or unexpected value — inspect $VPROP_DEV"
    fi

    # Verify the outcome, not that sed ran.
    if grep -q '^ro\.surface_flinger\.supports_background_blur=0$' "$VPROP_DEV" \
    && grep -q '^debug\.sf\.auto_latch_unsignaled=1$' "$VPROP_DEV"; then
        ok "verified: device tree now matches XT intent"
    else
        die "D7 verification failed in $VPROP_DEV"
    fi

    # No key may appear twice anywhere in this file: that is the exact condition
    # post_process_props.py rejects.
    dupes=$(grep -oE '^[A-Za-z0-9_.]+=' "$VPROP_DEV" | sort | uniq -d)
    if [[ -n "$dupes" ]]; then
        die "duplicate keys remain in $VPROP_DEV: $dupes"
    fi
    ok "verified: no duplicate keys in vendor.prop"
else
    warn "$VPROP_DEV absent — device tree not synced; nothing to patch"
fi

# ---------------------------------------------------------------------------
say "D8: sepolicy keys.conf needs testkey.* alongside our releasekey"
# ---------------------------------------------------------------------------
# Build died at 645/22,646 targets:
#
#   m4 ... system/sepolicy/private/keys.conf device/lineage/.../keys.conf
#   stderr: Path vendor/xt/keys/testkey.x509.pem does not exist or is not a file!
#
# Why: keys.conf:34-36 uses "$DEFAULT_SYSTEM_DEV_CERTIFICATE/testkey.x509.pem".
# DEFAULT_SYSTEM_DEV_CERTIFICATE resolves to vendor/xt/keys/releasekey, so the
# expansion is vendor/xt/keys/releasekey/testkey.x509.pem -- a nested path that
# cannot exist, because our key set is flat files whose base name is releasekey,
# not testkey. build/gen-release-keys.sh creates 19 files and no testkey at all.
#
# The tempting fix is to point PRODUCT_DEFAULT_DEV_CERTIFICATE at AOSP's
# build/make/target/product/security/testkey. That builds green and ships
# ro.build.tags=test-keys, which is on this project's never-ship list. So instead
# testkey.{x509.pem,pk8} are created as copies of OUR releasekey: sepolicy gets a
# file to open, and the certificate stays ours (CN = XT-OS releasekey).
#
KD="vendor/xt/keys"
if [[ -d "$KD" && -f "$KD/releasekey.x509.pem" && -f "$KD/releasekey.pk8" ]]; then
    made=""
    if [[ ! -f "$KD/testkey.x509.pem" ]]; then
        cp "$KD/releasekey.x509.pem" "$KD/testkey.x509.pem"
        chmod 644 "$KD/testkey.x509.pem"
        made="x509"
    fi
    if [[ ! -f "$KD/testkey.pk8" ]]; then
        cp "$KD/releasekey.pk8" "$KD/testkey.pk8"
        chmod 600 "$KD/testkey.pk8"
        made="$made pk8"
    fi
    if [[ -n "${made// /}" ]]; then
        ok "created testkey alias from releasekey ($made)"
    else
        ok "testkey alias already present"
    fi

    # The alias must be the SAME certificate as releasekey -- if someone replaced
    # it with AOSP's public testkey, signatures stop being ours and the release
    # guarantee silently disappears. Compare fingerprints instead of trusting
    # that the copy happened.
    fp_rel=$(openssl x509 -in "$KD/releasekey.x509.pem" -noout -fingerprint -sha256 2>/dev/null)
    fp_tst=$(openssl x509 -in "$KD/testkey.x509.pem" -noout -fingerprint -sha256 2>/dev/null)
    if [[ "$fp_rel" == "$fp_tst" && -n "$fp_rel" ]]; then
        ok "verified: testkey alias == releasekey ($(echo "$fp_rel" | sed 's/.*=//'))"
    else
        die "D8: testkey.x509.pem is NOT our releasekey — release signing would be lost"
    fi
else
    warn "$KD or releasekey.* absent — run build/gen-release-keys.sh first"
fi

# ---------------------------------------------------------------------------
say "Summary"
# ---------------------------------------------------------------------------
printf '    patches applied to %s\n' "$TREE"
printf '    next: . build/envsetup.sh && lunch xt_m31-userdebug && m bacon\n\n'
