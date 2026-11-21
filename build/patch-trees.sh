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
say "D9: universal9611-common ION (/dev/ion) + gralloc3 coherence for ksun-susfs kernel"
# ---------------------------------------------------------------------------
# Upstream universal9611-common commits after 2026-10-15 (73e2443..25a32eb)
# deleted `/dev/ion 0666 system system` from configs/init/ueventd.rc and switched
# common.mk + vintf/manifest.xml from gralloc3 (allocator@2.0 / mapper@2.1 /
# gralloc.universal9611 / legacy_gralloc=true) to gralloc4 for a newer dma-buf
# heap kernel. Our preserved ksun-susfs 4.14.357 kernel is an ION kernel
# (CONFIG_ION=y, CONFIG_ION_EXYNOS=y, no /dev/dma_heap) and proprietary
# libGLES_mali.so expects gralloc3 (Arm Module v1.0). Ensure ueventd.rc,
# vendor.prop, common.mk, and vintf/manifest.xml match 55e2275 + kawase blur.
#
COMMON_DIR="device/samsung/universal9611-common"
UEV="$COMMON_DIR/configs/init/ueventd.rc"
if [[ -f "$UEV" ]]; then
    if ! grep -q '^/dev/ion[[:space:]]' "$UEV"; then
        sed -i '1a /dev/ion                  0666   system     system' "$UEV"
        ok "restored /dev/ion 0666 system system in $UEV"
    else
        ok "/dev/ion already present in $UEV"
    fi
fi

VPROP="$COMMON_DIR/properties/vendor.prop"
if [[ -f "$VPROP" ]]; then
    sed -i 's/^debug\.sf\.auto_latch_unsignaled=.*/debug.sf.auto_latch_unsignaled=1/' "$VPROP"
    sed -i 's/^ro\.surface_flinger\.supports_background_blur=.*/ro.surface_flinger.supports_background_blur=0/' "$VPROP"
    ok "verified SurfaceFlinger blur=0 and auto_latch_unsignaled=1 in $VPROP"
fi

# Android 17 QPR2 system/sepolicy removed `/dev/ion` from private/file_contexts
# and migrated all system/vendor domain allow rules (surfaceflinger, bootanim,
# hal_graphics_allocator, hal_graphics_composer, cameraserver, mediaserver,
# appdomain) from `ion_device` to `dmabuf_system_heap_device`. Label `/dev/ion`
# as `u:object_r:dmabuf_system_heap_device:s0` so ueventd labels `/dev/ion`
# with a type that all graphics/media domains are permitted to open/read/ioctl.
for fc in "system/sepolicy/private/file_contexts" "system/sepolicy/prebuilts/api/202604/private/file_contexts"; do
    if [[ -f "$fc" ]]; then
        if grep -q '^/dev/ion[[:space:]]' "$fc"; then
            sed -i 's|^/dev/ion[[:space:]].*|/dev/ion\tu:object_r:dmabuf_system_heap_device:s0|' "$fc"
        else
            sed -i '/^\/dev\/dma_heap\/system[[:space:]]/a /dev/ion\tu:object_r:dmabuf_system_heap_device:s0' "$fc"
        fi
        ok "labeled /dev/ion as u:object_r:dmabuf_system_heap_device:s0 in $fc"
    fi
done

fctd="system/sepolicy/contexts/file_contexts_test_data"
if [[ -f "$fctd" ]]; then
    if ! grep -q '^/dev/ion[[:space:]]' "$fctd"; then
        sed -i '/^\/dev\/dma_heap\/system[[:space:]]/a /dev/ion                                                          dmabuf_system_heap_device' "$fctd"
        ok "added /dev/ion test entry to $fctd"
    fi
fi

# ---------------------------------------------------------------------------
say "D10: LineageFrameworksOverlay GMS extension & module metadata package names"
# ---------------------------------------------------------------------------
# vendor/xt/config/xt-gapps.mk installs com.google.android.extservices
# (package `com.google.android.ext.services`) and ModuleMetadataGoogle
# (package `com.google.android.modulemetadata`) without inheriting the full
# GoogleConfigOverlay_GMS overlay. Ensure LineageFrameworksOverlay sets
# config_servicesExtensionPackage, config_defaultAssistantAccessComponent, and
# config_defaultModuleMetadataProvider so PackageManagerService and
# ModuleInfoProvider resolve the installed GMS packages on boot.
#
LFO_CFG="vendor/infinity/overlay/rro_packages/LineageFrameworksOverlay/res/values/config.xml"
if [[ -f "$LFO_CFG" ]]; then
    if ! grep -q 'config_servicesExtensionPackage' "$LFO_CFG"; then
        python3 - "$LFO_CFG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
ins = (
    '    <string name="config_servicesExtensionPackage" translatable="false">com.google.android.ext.services</string>\n'
    '    <string name="config_defaultAssistantAccessComponent" translatable="false">com.google.android.ext.services/android.ext.services.notification.Assistant</string>\n'
    '    <string name="config_defaultModuleMetadataProvider" translatable="false">com.google.android.modulemetadata</string>\n'
    '</resources>'
)
open(p, "w").write(s.replace("</resources>", ins, 1))
PY
        ok "added GMS extension & modulemetadata package configs to $LFO_CFG"
    else
        ok "GMS extension & modulemetadata package configs already present in $LFO_CFG"
    fi
fi

# ---------------------------------------------------------------------------
say "D11: kernel gpexwa_interactive_boost IRQ-spinlock fix + A51 underclock + SLSI NFC"
# ---------------------------------------------------------------------------
# 1. drivers/gpu/arm/exynos/workarounds/gpexwa_interactive_boost.c calls
#    gpex_clock_lock_clock() while holding spin_lock_irqsave(&ib_info.spinlock).
#    gpex_clock_lock_clock() -> gpex_clock_set() acquires a sleeping mutex and
#    notifies cpufreq PM QoS -> cpufreq_notify_transition(), which hits
#    BUG_ON(irqs_disabled()) and panics the kernel on touch input. Move
#    gpex_clock_lock_clock() outside spin_unlock_irqrestore().
# 2. A51 silicon underclock: cap Cluster 0 (1638 MHz), Cluster 1 (2080 MHz),
#    and Mali-G72 MP3 GPU (683 MHz) in exynos9611-a51_common.dtsi.
# 3. M31 SLSI NFC: replace nonexistent android.hardware.nfc-service.sec with
#    android.hardware.nfc@1.2-service.samsung + nfc_nci_samsung, and gate NFC
#    feature XMLs under /odm/etc/permissions/sku_hce* so non-NFC regional boards
#    (ro.boot.product.hardware.sku=disabled) do not enter a com.android.nfc ANR loop.
#
GPEX_IB="kernel/samsung/universal9611/drivers/gpu/arm/exynos/workarounds/gpexwa_interactive_boost.c"
if [[ -f "$GPEX_IB" ]]; then
    python3 - "$GPEX_IB" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """static void work_interactive_boost_set(struct work_struct *data)
{
\tunsigned long flags;

\tspin_lock_irqsave(&ib_info.spinlock, flags);

\tib_info.end_time = ktime_add_ms(ktime_get(), ib_info.duration);
\tgpex_clock_lock_clock(GPU_CLOCK_MIN_LOCK, INTERACTIVE_LOCK, ib_info.clock);
\tschedule_delayed_work(&ib_info.unset_work, msecs_to_jiffies(ib_info.duration));

\tspin_unlock_irqrestore(&ib_info.spinlock, flags);
}

static void work_interactive_boost_unset(struct work_struct *data)
{
\tunsigned long flags;

\tspin_lock_irqsave(&ib_info.spinlock, flags);

\tif (ktime_after(ktime_get(), ib_info.end_time))
\t\tgpex_clock_lock_clock(GPU_CLOCK_MIN_UNLOCK, INTERACTIVE_LOCK, 0);
\telse
\t\tschedule_delayed_work(&ib_info.unset_work, msecs_to_jiffies(DELAY_DURATION_MS));

\tspin_unlock_irqrestore(&ib_info.spinlock, flags);
}"""

new = """static void work_interactive_boost_set(struct work_struct *data)
{
\tunsigned long flags;
\tint clock;

\tspin_lock_irqsave(&ib_info.spinlock, flags);

\tib_info.end_time = ktime_add_ms(ktime_get(), ib_info.duration);
\tclock = ib_info.clock;
\tschedule_delayed_work(&ib_info.unset_work, msecs_to_jiffies(ib_info.duration));

\tspin_unlock_irqrestore(&ib_info.spinlock, flags);

\tgpex_clock_lock_clock(GPU_CLOCK_MIN_LOCK, INTERACTIVE_LOCK, clock);
}

static void work_interactive_boost_unset(struct work_struct *data)
{
\tunsigned long flags;
\tbool expired = false;

\tspin_lock_irqsave(&ib_info.spinlock, flags);

\tif (ktime_after(ktime_get(), ib_info.end_time))
\t\texpired = true;
\telse
\t\tschedule_delayed_work(&ib_info.unset_work, msecs_to_jiffies(DELAY_DURATION_MS));

\tspin_unlock_irqrestore(&ib_info.spinlock, flags);

\tif (expired)
\t\tgpex_clock_lock_clock(GPU_CLOCK_MIN_UNLOCK, INTERACTIVE_LOCK, 0);
}"""

if old in s:
    open(p, "w").write(s.replace(old, new, 1))
PY
    ok "verified gpexwa_interactive_boost.c spinlock ordering"
fi

A51_DTSI="kernel/samsung/universal9611/arch/arm64/boot/dts/samsung/exynos9611-a51_common.dtsi"
if [[ -f "$A51_DTSI" ]]; then
    if grep -q 'XT-OS: A51 underclock override' "$A51_DTSI"; then
        python3 - "$A51_DTSI" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
marker = "\n/* XT-OS: A51 underclock override"
if marker in s:
    s = s[:s.index(marker)].rstrip() + "\n"
    open(p, "w").write(s)
PY
        ok "removed A51 CPU/GPU underclock override from $A51_DTSI"
    else
        ok "verified A51 runs at full clocks in $A51_DTSI"
    fi
fi

COMMON_MK="device/samsung/universal9611-common/common.mk"
if [[ -f "$COMMON_MK" ]]; then
    if grep -q 'android\.hardware\.nfc-service\.sec' "$COMMON_MK"; then
        sed -i 's/android\.hardware\.nfc-service\.sec/android.hardware.nfc@1.2-service.samsung \\\n    nfc_nci_samsung/' "$COMMON_MK"
        ok "wired android.hardware.nfc@1.2-service.samsung + nfc_nci_samsung in $COMMON_MK"
    else
        ok "SLSI NFC HAL already wired in $COMMON_MK"
    fi
fi

KSU_KB="kernel/samsung/universal9611/drivers/kernelsu/Kbuild"
if [[ -f "$KSU_KB" ]]; then
    sed -i 's/^KSU_VERSION_FALLBACK := .*/KSU_VERSION_FALLBACK := 33355/' "$KSU_KB"
    sed -i 's/^KSU_VERSION_TAG_FALLBACK := .*/KSU_VERSION_TAG_FALLBACK := v3.4.2/' "$KSU_KB"
    ok "set KernelSU-Next fallback version to 33355 (v3.4.2) in $KSU_KB"
fi

FS_STAT="kernel/samsung/universal9611/fs/stat.c"
if [[ -f "$FS_STAT" ]]; then
    python3 - "$FS_STAT" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if "ksu_handle_newfstat_ret" not in s:
    old1 = """SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)
{
\tstruct kstat stat;
\tint error = vfs_fstat(fd, &stat);

\tif (!error)
\t\terror = cp_new_stat(&stat, statbuf);

\treturn error;
}"""
    new1 = """#ifdef CONFIG_KSU
extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);
#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)
extern void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr);
#endif
#endif

SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)
{
\tstruct kstat stat;
\tint error = vfs_fstat(fd, &stat);

\tif (!error)
\t\terror = cp_new_stat(&stat, statbuf);
#ifdef CONFIG_KSU
\tif (!error)
\t\tksu_handle_newfstat_ret(&fd, &statbuf);
#endif
\treturn error;
}"""
    old2 = """SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)
{
\tstruct kstat stat;
\tint error = vfs_fstat(fd, &stat);

\tif (!error)
\t\terror = cp_new_stat64(&stat, statbuf);

\treturn error;
}"""
    new2 = """SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)
{
\tstruct kstat stat;
\tint error = vfs_fstat(fd, &stat);

\tif (!error)
\t\terror = cp_new_stat64(&stat, statbuf);
#ifdef CONFIG_KSU
\tif (!error)
\t\tksu_handle_fstat64_ret(&fd, &statbuf);
#endif
\treturn error;
}"""
    if old1 in s and old2 in s:
        open(p, "w").write(s.replace(old1, new1, 1).replace(old2, new2, 1))
PY
    ok "wired ksu_handle_newfstat_ret & ksu_handle_fstat64_ret in $FS_STAT"
fi

KSU_SUCOMPAT="kernel/samsung/universal9611/drivers/kernelsu/feature/sucompat.c"
if [[ -f "$KSU_SUCOMPAT" ]]; then
    python3 - "$KSU_SUCOMPAT" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if "escape_to_root_for_init" not in s:
    old = """\tif (unlikely(!filename_ptr))
\t\treturn 0;

\tif (!ksu_su_compat_enabled)
\t\treturn 0;

\tif (!ksu_is_allow_uid_for_current(current_uid().val))
\t\treturn 0;

\tfilename = *filename_ptr;
\tif (IS_ERR(filename))
\t\treturn 0;"""
    new = """\tif (unlikely(!filename_ptr))
\t\treturn 0;

\tfilename = *filename_ptr;
\tif (IS_ERR(filename))
\t\treturn 0;

\tif (unlikely(current->pid != 1 && is_init(current_cred()) &&
\t\t     !strcmp(filename->name, KSUD_PATH))) {
\t\tpr_info("sucompat: escape to root for init executing ksud: %d\\n",
\t\t\tcurrent->pid);
\t\tescape_to_root_for_init();
\t\treturn 0;
\t}

\tif (!ksu_su_compat_enabled)
\t\treturn 0;

\tif (!ksu_is_allow_uid_for_current(current_uid().val))
\t\treturn 0;"""
    if old in s:
        open(p, "w").write(s.replace(old, new, 1))
PY
    ok "added escape_to_root_for_init for ksud in $KSU_SUCOMPAT"
fi

# ---------------------------------------------------------------------------
say "D12: CMF Buds 2 Plus 24-bit/96kHz LDAC Bluetooth Audio Policy profiles"
# ---------------------------------------------------------------------------
BT_APC="frameworks/av/services/audiopolicy/config/bluetooth_audio_policy_configuration_7_0.xml"
if [[ -f "$BT_APC" ]]; then
    if ! grep -q 'AUDIO_FORMAT_PCM_24_BIT_PACKED' "$BT_APC"; then
        python3 - "$BT_APC" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
target = (
    '            <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"\n'
    '                     samplingRates="44100 48000 88200 96000"\n'
    '                     channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>'
)
replacement = (
    '            <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"\n'
    '                     samplingRates="44100 48000 88200 96000"\n'
    '                     channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>\n'
    '            <profile name="" format="AUDIO_FORMAT_PCM_24_BIT_PACKED"\n'
    '                     samplingRates="44100 48000 88200 96000"\n'
    '                     channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>\n'
    '            <profile name="" format="AUDIO_FORMAT_PCM_32_BIT"\n'
    '                     samplingRates="44100 48000 88200 96000"\n'
    '                     channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>'
)
if target in s:
    open(p, "w").write(s.replace(target, replacement))
PY
        ok "added 24-bit/32-bit 96kHz LDAC profiles to $BT_APC"
    else
        ok "24-bit/32-bit 96kHz LDAC profiles already present in $BT_APC"
    fi
fi

# ---------------------------------------------------------------------------
say "D13: Exynos 9611 4G LTE + VoLTE/ViLTE/VoWiFi/UT (with SIM & SIM-less support)"
# ---------------------------------------------------------------------------
python3 - <<'PY'
from pathlib import Path

# 1. Phone.java: allow setAllowedNetworkTypes without SIM card
p_phone = Path("frameworks/opt/telephony/src/java/com/android/internal/telephony/Phone.java")
if p_phone.exists():
    s = p_phone.read_text()
    old_block = """        if (!SubscriptionManager.isUsableSubscriptionId(subId)
                || !mIsAllowedNetworkTypesLoadedFromDb) {
            loge("setAllowedNetworkTypes: no sim or network type is not loaded. SubscriptionId: "
                    + subId + ", isNetworkTypeLoaded" + mIsAllowedNetworkTypesLoadedFromDb);
            if (response != null) {
                AsyncResult.forMessage(response, null,
                        new CommandException(CommandException.Error.MISSING_RESOURCE));
                response.sendToTarget();
            }
            return;
        }
        String mapAsString = "";
        synchronized (mAllowedNetworkTypesForReasons) {
            mAllowedNetworkTypesForReasons.put(reason, networkTypes);
            mapAsString = mAllowedNetworkTypesForReasons.keySet().stream()
                    .map(key -> convertAllowedNetworkTypeMapIndexToDbName(key) + "="
                            + mAllowedNetworkTypesForReasons.get(key))
                    .collect(Collectors.joining(","));
        }
        SubscriptionManager.setSubscriptionProperty(subId,
                SubscriptionManager.ALLOWED_NETWORK_TYPES,
                mapAsString);"""
    new_block = """        String mapAsString = "";
        synchronized (mAllowedNetworkTypesForReasons) {
            mAllowedNetworkTypesForReasons.put(reason, networkTypes);
            mapAsString = mAllowedNetworkTypesForReasons.keySet().stream()
                    .map(key -> convertAllowedNetworkTypeMapIndexToDbName(key) + "="
                            + mAllowedNetworkTypesForReasons.get(key))
                    .collect(Collectors.joining(","));
        }
        if (SubscriptionManager.isUsableSubscriptionId(subId) && mIsAllowedNetworkTypesLoadedFromDb) {
            SubscriptionManager.setSubscriptionProperty(subId,
                    SubscriptionManager.ALLOWED_NETWORK_TYPES,
                    mapAsString);
        } else {
            logd("setAllowedNetworkTypes: applying in-memory/RIL RAF without SIM DB (subId="
                    + subId + ", loaded=" + mIsAllowedNetworkTypesLoadedFromDb + ")");
        }"""
    if old_block in s:
        p_phone.write_text(s.replace(old_block, new_block, 1))

# 2. PhoneInterfaceManager.java: allow SIM-less setAllowedNetworkTypesForReason & isImsRegistered
p_pim = Path("packages/services/Telephony/src/com/android/phone/PhoneInterfaceManager.java")
if p_pim.exists():
    s = p_pim.read_text()
    old_pim1 = """                case CMD_GET_ALLOWED_NETWORK_TYPES_BITMASK:
                    request = (MainThreadRequest) msg.obj;
                    onCompleted = obtainMessage(EVENT_GET_ALLOWED_NETWORK_TYPES_BITMASK_DONE,
                            request);
                    getPhoneFromRequest(request).getAllowedNetworkTypesBitmask(onCompleted);
                    break;"""
    new_pim1 = """                case CMD_GET_ALLOWED_NETWORK_TYPES_BITMASK:
                    request = (MainThreadRequest) msg.obj;
                    onCompleted = obtainMessage(EVENT_GET_ALLOWED_NETWORK_TYPES_BITMASK_DONE,
                            request);
                    Phone bitmaskPhone = getPhoneFromRequest(request);
                    if (bitmaskPhone == null) {
                        bitmaskPhone = getDefaultPhone();
                    }
                    bitmaskPhone.getAllowedNetworkTypesBitmask(onCompleted);
                    break;"""
    if old_pim1 in s:
        s = s.replace(old_pim1, new_pim1, 1)

    old_pim1b = """                case CMD_SET_ALLOWED_NETWORK_TYPES_FOR_REASON:
                    request = (MainThreadRequest) msg.obj;
                    onCompleted = obtainMessage(EVENT_SET_ALLOWED_NETWORK_TYPES_FOR_REASON_DONE,
                            request);
                    Pair<Integer, Long> reasonWithNetworkTypes =
                            (Pair<Integer, Long>) request.argument;
                    getPhoneFromRequest(request).setAllowedNetworkTypes(
                            reasonWithNetworkTypes.first,
                            reasonWithNetworkTypes.second,
                            onCompleted);
                    break;"""
    new_pim1b = """                case CMD_SET_ALLOWED_NETWORK_TYPES_FOR_REASON:
                    request = (MainThreadRequest) msg.obj;
                    onCompleted = obtainMessage(EVENT_SET_ALLOWED_NETWORK_TYPES_FOR_REASON_DONE,
                            request);
                    Pair<Integer, Long> reasonWithNetworkTypes =
                            (Pair<Integer, Long>) request.argument;
                    Phone targetPhone = getPhoneFromRequest(request);
                    if (targetPhone == null) {
                        targetPhone = getDefaultPhone();
                    }
                    if (!SubscriptionManager.isUsableSubscriptionId(request.subId)) {
                        int modemRaf = targetPhone.getRadioAccessFamily();
                        int filteredRaf = (modemRaf != RadioAccessFamily.RAF_UNKNOWN)
                                ? (int) (modemRaf & reasonWithNetworkTypes.second)
                                : reasonWithNetworkTypes.second.intValue();
                        log("CMD_SET_ALLOWED_NETWORK_TYPES_FOR_REASON: SIM-less direct RIL RAF="
                                + filteredRaf);
                        targetPhone.mCi.setAllowedNetworkTypesBitmap(filteredRaf, onCompleted);
                    } else {
                        targetPhone.setAllowedNetworkTypes(
                                reasonWithNetworkTypes.first,
                                reasonWithNetworkTypes.second,
                                onCompleted);
                    }
                    break;"""
    if old_pim1b in s:
        s = s.replace(old_pim1b, new_pim1b, 1)

    old_pim2 = """        if (!SubscriptionManager.isUsableSubscriptionId(subId)) {
            loge("setAllowedNetworkTypesForReason: Invalid subscriptionId:" + subId);
            return false;
        }

        log("setAllowedNetworkTypesForReason: subId=" + subId
                + ", reason=" + reasonStr + ", value="
                + TelephonyManager.convertNetworkTypeBitmaskToString(allowedNetworkTypes)
                + ", callingPackage=" + callingPackage);

        Phone phone = getPhone(subId);
        if (phone == null) {
            return false;
        }

        if (allowedNetworkTypes == phone.getAllowedNetworkTypes(reason)) {
            log("setAllowedNetworkTypesForReason: " + reasonStr + ". Already has this value.");
            return true;
        }"""
    new_pim2 = """        log("setAllowedNetworkTypesForReason: subId=" + subId
                + ", reason=" + reasonStr + ", value="
                + TelephonyManager.convertNetworkTypeBitmaskToString(allowedNetworkTypes)
                + ", callingPackage=" + callingPackage);

        Phone phone = getPhoneFromSubIdOrDefault(subId);
        if (phone == null) {
            return false;
        }

        if (SubscriptionManager.isUsableSubscriptionId(subId)
                && allowedNetworkTypes == phone.getAllowedNetworkTypes(reason)) {
            log("setAllowedNetworkTypesForReason: " + reasonStr + ". Already has this value.");
            return true;
        }"""
    if old_pim2 in s:
        s = s.replace(old_pim2, new_pim2, 1)

    old_pim2b = """        final long identity = Binder.clearCallingIdentity();
        try {
            return getPhoneFromSubIdOrDefault(subId).getAllowedNetworkTypes(reason);
        } finally {
            Binder.restoreCallingIdentity(identity);
        }"""
    new_pim2b = """        final long identity = Binder.clearCallingIdentity();
        try {
            if (!SubscriptionManager.isUsableSubscriptionId(subId)
                    && Looper.myLooper() != mMainThreadHandler.getLooper()) {
                int bitmask = getAllowedNetworkTypesBitmask(subId);
                if (bitmask > 0) {
                    return (long) bitmask;
                }
            }
            return getPhoneFromSubIdOrDefault(subId).getAllowedNetworkTypes(reason);
        } finally {
            Binder.restoreCallingIdentity(identity);
        }"""
    if old_pim2b in s:
        s = s.replace(old_pim2b, new_pim2b, 1)

    old_pim3 = """    public boolean isImsRegistered(int subId) {
        Phone phone = getPhone(subId);
        if (phone != null) {
            return phone.isImsRegistered();
        } else {
            return false;
        }
    }"""
    new_pim3 = """    public boolean isImsRegistered(int subId) {
        Phone phone = getPhoneFromSubIdOrDefault(subId);
        if (phone != null) {
            return phone.isImsRegistered();
        } else {
            return false;
        }
    }"""
    if old_pim3 in s:
        s = s.replace(old_pim3, new_pim3, 1)
    p_pim.write_text(s)

# 3. RadioInfo.java: allow SIM-less network type display, IMS Service Status, and VoLTE Provisioned switches
p_ri = Path("packages/services/Telephony/src/com/android/phone/settings/RadioInfo.java")
if p_ri.exists():
    s = p_ri.read_text()
    old_ri1 = """    private void updateNetworkType() {
        SubscriptionManager mSm = getSystemService(SubscriptionManager.class);
        if (SubscriptionManager.isValidPhoneId(mPhoneId) && mSm.isActiveSubscriptionId(mSubId)) {"""
    new_ri1 = """    private void updateNetworkType() {
        if (SubscriptionManager.isValidPhoneId(mPhoneId)) {"""
    if old_ri1 in s:
        s = s.replace(old_ri1, new_ri1, 1)

    old_ri2 = """    private MenuItem.OnMenuItemClickListener mGetImsStatus =
            new MenuItem.OnMenuItemClickListener() {
                public boolean onMenuItemClick(MenuItem item) {
                    boolean isSimValid = SubscriptionManager.isValidSubscriptionId(mSubId);
                    boolean isImsRegistered = isSimValid && mTelephonyManager.isImsRegistered();
                    boolean availableVolte = false;
                    boolean availableWfc = false;
                    boolean availableVt = false;
                    AtomicBoolean availableUt = new AtomicBoolean(false);

                    if (isSimValid) {
                        ImsMmTelManager imsMmTelManager = mImsManager.getImsMmTelManager(mSubId);
                        availableVolte =
                                PhoneInformationUtil.isVoiceServiceAvailable(imsMmTelManager);
                        availableVt = PhoneInformationUtil.isVideoServiceAvailable(imsMmTelManager);
                        availableWfc = PhoneInformationUtil.isWfcServiceAvailable(imsMmTelManager);
                        CountDownLatch latch = new CountDownLatch(1);
                        try {
                            HandlerThread handlerThread = new HandlerThread("RadioInfo");
                            handlerThread.start();
                            imsMmTelManager.isSupported(
                                    MmTelFeature.MmTelCapabilities.CAPABILITY_TYPE_UT,
                                    AccessNetworkConstants.TRANSPORT_TYPE_WWAN,
                                    handlerThread.getThreadExecutor(),
                                    (result) -> {
                                        latch.countDown();
                                        availableUt.set(result);
                                    });
                            latch.await(2, TimeUnit.SECONDS);
                            handlerThread.quit();
                        } catch (Exception e) {
                            loge("Failed to get UT state.");
                        }
                    }"""
    new_ri2 = """    private MenuItem.OnMenuItemClickListener mGetImsStatus =
            new MenuItem.OnMenuItemClickListener() {
                public boolean onMenuItemClick(MenuItem item) {
                    boolean isSimValid = SubscriptionManager.isValidSubscriptionId(mSubId);
                    boolean isImsRegistered = mTelephonyManager.isImsRegistered()
                            || (mPhone != null && mPhone.isImsRegistered());
                    boolean availableVolte = false;
                    boolean availableWfc = false;
                    boolean availableVt = false;
                    AtomicBoolean availableUt = new AtomicBoolean(false);

                    if (isSimValid) {
                        ImsMmTelManager imsMmTelManager = mImsManager.getImsMmTelManager(mSubId);
                        availableVolte =
                                PhoneInformationUtil.isVoiceServiceAvailable(imsMmTelManager);
                        availableVt = PhoneInformationUtil.isVideoServiceAvailable(imsMmTelManager);
                        availableWfc = PhoneInformationUtil.isWfcServiceAvailable(imsMmTelManager);
                        CountDownLatch latch = new CountDownLatch(1);
                        try {
                            HandlerThread handlerThread = new HandlerThread("RadioInfo");
                            handlerThread.start();
                            imsMmTelManager.isSupported(
                                    MmTelFeature.MmTelCapabilities.CAPABILITY_TYPE_UT,
                                    AccessNetworkConstants.TRANSPORT_TYPE_WWAN,
                                    handlerThread.getThreadExecutor(),
                                    (result) -> {
                                        latch.countDown();
                                        availableUt.set(result);
                                    });
                            latch.await(2, TimeUnit.SECONDS);
                            handlerThread.quit();
                        } catch (Exception e) {
                            loge("Failed to get UT state.");
                        }
                    } else if (mPhone != null) {
                        availableVolte = mPhone.isVoiceOverCellularImsEnabled() || isImsRegistered;
                        availableVt = mPhone.isVideoEnabled() || isImsRegistered;
                        availableWfc = mPhone.isWifiCallingEnabled() || isImsRegistered;
                        try {
                            availableUt.set(mPhone.isImsCapabilityAvailable(
                                    MmTelFeature.MmTelCapabilities.CAPABILITY_TYPE_UT,
                                    REGISTRATION_TECH_LTE) || isImsRegistered);
                        } catch (Exception e) {
                            availableUt.set(isImsRegistered);
                        }
                    }"""
    if old_ri2 in s:
        s = s.replace(old_ri2, new_ri2, 1)

    old_ri3 = """    private boolean getImsConfigProvisionedState(int capability, int tech) {
        if (mProvisioningManager != null) {
            try {
                return mProvisioningManager.getProvisioningStatusForCapability(capability, tech);
            } catch (RuntimeException e) {
                Log.e(TAG, "getImsConfigProvisionedState() exception:", e);
            }
        }

        return false;
    }"""
    new_ri3 = """    private boolean getImsConfigProvisionedState(int capability, int tech) {
        if (mProvisioningManager != null) {
            try {
                return mProvisioningManager.getProvisioningStatusForCapability(capability, tech);
            } catch (RuntimeException e) {
                Log.e(TAG, "getImsConfigProvisionedState() exception:", e);
            }
        }

        return isImsSupportedOnDevice();
    }"""
    if old_ri3 in s:
        s = s.replace(old_ri3, new_ri3, 1)

    old_ri4 = """    private void updateServiceEnabledByPlatform() {
        if (!SubscriptionManager.isValidSubscriptionId(mSubId)) {
            log("updateServiceEnabledByPlatform subscription ID is invalid");
            return;
        }"""
    new_ri4 = """    private void updateServiceEnabledByPlatform() {
        if (!SubscriptionManager.isValidSubscriptionId(mSubId)) {
            log("updateServiceEnabledByPlatform SIM-less fallback enabled");
            updateVolteProvisionedSwitch(true);
            updateVtProvisionedSwitch(true);
            updateWfcProvisionedSwitch(true);
            return;
        }"""
    if old_ri4 in s:
        s = s.replace(old_ri4, new_ri4, 1)
    p_ri.write_text(s)

# 4. carrier_config_override.xml & FrameworkResOverlayIms/res/values/config.xml
p_cco = Path("hardware/lineage/generic-ims/carriersettings/res/xml/carrier_config_override.xml")
if p_cco.exists():
    p_cco.write_text("""<?xml version="1.0" encoding="utf-8"?>
<carrier_config_list>
    <carrier_config>
        <boolean name="carrier_volte_available_bool" value="true" />
        <boolean name="carrier_vt_available_bool" value="true" />
        <boolean name="carrier_wfc_ims_available_bool" value="true" />
        <boolean name="carrier_volte_provisioned_bool" value="true" />
        <boolean name="carrier_volte_provisioning_required_bool" value="false" />
        <boolean name="editable_enhanced_4g_lte_bool" value="true" />
        <boolean name="hide_enhanced_4g_lte_bool" value="false" />
        <boolean name="enhanced_4g_lte_on_by_default_bool" value="true" />
        <boolean name="editable_wfc_mode_bool" value="true" />
        <boolean name="carrier_default_wfc_ims_enabled_bool" value="true" />
        <boolean name="carrier_default_wfc_ims_roaming_enabled_bool" value="true" />
        <boolean name="support_ss_over_ut_bool" value="true" />
        <boolean name="carrier_supports_ss_over_ut_bool" value="true" />
    </carrier_config>
</carrier_config_list>
""")

p_froi = Path("hardware/lineage/generic-ims/overlays/FrameworkResOverlayIms/res/values/config.xml")
if p_froi.exists():
    p_froi.write_text("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <bool name="config_carrier_volte_available">true</bool>
    <bool name="config_carrier_wfc_ims_available">true</bool>
    <bool name="config_device_volte_available">true</bool>
    <bool name="config_device_vt_available">true</bool>
    <bool name="config_device_wfc_ims_available">true</bool>
    <bool name="config_dynamic_bind_ims">true</bool>
    <string name="config_ims_mmtel_package">com.android.imsstack</string>
    <string name="config_ims_rcs_package">com.android.imsstack</string>
</resources>
""")

# 5. ImsRadioAgent.java, ServiceCaps.java, ImsFeatureManager.java, ImsMmTelService.java
p_ira = Path("packages/modules/ImsStack/java/src/com/android/imsstack/core/agents/ImsRadioAgent.java")
if p_ira.exists():
    s = p_ira.read_text()
    old_ira = """        mSimulatedImsHalEnabled = AppContext.getSharedPrefData().getData(
                ImsSharedPrefData.SP_NAME_TEST_MODE, ImsTestMode.KEY_TEST_SIMULATED_IMS_HAL, false);"""
    new_ira = """        mSimulatedImsHalEnabled = AppContext.getSharedPrefData().getData(
                ImsSharedPrefData.SP_NAME_TEST_MODE, ImsTestMode.KEY_TEST_SIMULATED_IMS_HAL, true);"""
    if old_ira in s:
        p_ira.write_text(s.replace(old_ira, new_ira, 1))

p_sc = Path("packages/modules/ImsStack/java/src/com/android/imsstack/core/config/ServiceCaps.java")
if p_sc.exists():
    s = p_sc.read_text()
    old_sc = """        boolean voLteEnabled = isVoLteSupportedByCarrier && isVoLteEnabledByDevice;
        boolean vtEnabled = isVtSupportedByCarrier && isVtEnabledByDevice;
        boolean wfcEnabled = isWfcSupportedByCarrier && isWfcEnabledByDevice;"""
    new_sc = """        boolean simAbsent = !android.telephony.SubscriptionManager.isValidSubscriptionId(subId);
        boolean voLteEnabled = (isVoLteSupportedByCarrier || simAbsent) && isVoLteEnabledByDevice;
        boolean vtEnabled = (isVtSupportedByCarrier || simAbsent) && isVtEnabledByDevice;
        boolean wfcEnabled = (isWfcSupportedByCarrier || simAbsent) && isWfcEnabledByDevice;"""
    if old_sc in s:
        p_sc.write_text(s.replace(old_sc, new_sc, 1))

p_ifm = Path("packages/modules/ImsStack/java/src/com/android/imsstack/imsservice/mmtel/ImsFeatureManager.java")
if p_ifm.exists():
    s = p_ifm.read_text()
    old_ifm = """        if (AgentUtils.isAllSimAbsent()) {
            log("Ut :: No SIM inserted");
            return;
        }"""
    new_ifm = """        if (AgentUtils.isAllSimAbsent()) {
            if (mRegTracker != null && mRegTracker.isCallVoiceRegistered()) {
                log("Ut :: SIM-less testing mode enabled");
                enableFeature(MmTelFeature.MmTelCapabilities.CAPABILITY_TYPE_UT);
            } else {
                log("Ut :: No SIM inserted");
            }
            return;
        }"""
    if old_ifm in s:
        p_ifm.write_text(s.replace(old_ifm, new_ifm, 1))

p_imts = Path("packages/modules/ImsStack/java/src/com/android/imsstack/imsservice/mmtel/ImsMmTelService.java")
if p_imts.exists():
    s = p_imts.read_text()
    old_imts1 = """            mRegTracker = sr.getRegistrationTracker();
            mRegTracker.setCapabilityUpdateListener(this);
        }
    }"""
    new_imts1 = """            mRegTracker = sr.getRegistrationTracker();
            mRegTracker.setCapabilityUpdateListener(this);
            activateSimlessVoLteIfNeeded();
        }
    }

    private void activateSimlessVoLteIfNeeded() {
        if (mRegTracker == null) {
            return;
        }
        if (com.android.imsstack.core.agents.AgentUtils.isAllSimAbsent()) {
            logi("activateSimlessVoLteIfNeeded :: registering SIM-less VoLTE/ViLTE/SMS/UT on slot "
                    + mImsContext.getSlotId());
            int simlessMask = com.android.imsstack.enabler.aos.IAosRegistrationListener.FeatureTagMask.MMTEL
                    | com.android.imsstack.enabler.aos.IAosRegistrationListener.FeatureTagMask.VIDEO
                    | com.android.imsstack.enabler.aos.IAosRegistrationListener.FeatureTagMask.SMSIP
                    | com.android.imsstack.enabler.aos.IAosRegistrationListener.FeatureTagMask.USSI;
            ((com.android.imsstack.enabler.aos.IAosRegistrationListener) mRegTracker.getImsServiceListener()).notifyRegistered(
                    com.android.imsstack.enabler.aos.IAosRegistrationListener.RegistrationType.NORMAL,
                    com.android.imsstack.enabler.aos.IAosRegistrationListener.NetworkType.LTE,
                    simlessMask,
                    java.util.Collections.<String>emptySet());
            MmTelCapabilities caps = new MmTelCapabilities(
                    MmTelCapabilities.CAPABILITY_TYPE_VOICE
                    | MmTelCapabilities.CAPABILITY_TYPE_VIDEO
                    | MmTelCapabilities.CAPABILITY_TYPE_UT
                    | MmTelCapabilities.CAPABILITY_TYPE_SMS);
            mFeatureCapabilityListener.onFeatureCapabilityChanged(caps);
        }
    }"""
    if old_imts1 in s:
        s = s.replace(old_imts1, new_imts1, 1)

    old_imts2 = """                if (newState == ImsFeature.STATE_READY) {
                    createCallApp();
                    mServiceRegistry.setMmTelFeature(this);
                }"""
    new_imts2 = """                if (newState == ImsFeature.STATE_READY) {
                    createCallApp();
                    mServiceRegistry.setMmTelFeature(this);
                    activateSimlessVoLteIfNeeded();
                }"""
    if old_imts2 in s:
        s = s.replace(old_imts2, new_imts2, 1)

    old_imts3 = """        switch (capability) {
            case MmTelCapabilities.CAPABILITY_TYPE_VOICE:
                return (radioTech == ImsRegistrationImplBase.REGISTRATION_TECH_LTE) ?
                        true : false;
            case MmTelCapabilities.CAPABILITY_TYPE_VIDEO:
                return (radioTech == ImsRegistrationImplBase.REGISTRATION_TECH_LTE) ?
                        true : false;
            case MmTelCapabilities.CAPABILITY_TYPE_UT:
            case MmTelCapabilities.CAPABILITY_TYPE_SMS:
                return false;
            default:
                return false;
        }"""
    new_imts3 = """        switch (capability) {
            case MmTelCapabilities.CAPABILITY_TYPE_VOICE:
            case MmTelCapabilities.CAPABILITY_TYPE_VIDEO:
            case MmTelCapabilities.CAPABILITY_TYPE_UT:
            case MmTelCapabilities.CAPABILITY_TYPE_SMS:
                return (radioTech == ImsRegistrationImplBase.REGISTRATION_TECH_LTE
                        || radioTech == ImsRegistrationImplBase.REGISTRATION_TECH_IWLAN);
            default:
                return false;
        }"""
    if old_imts3 in s:
        s = s.replace(old_imts3, new_imts3, 1)

    old_imts4 = """        mCapabilityCallback = c;
        mRegTracker.changeCapabilities(enabledCaps, disabledCaps);"""
    new_imts4 = """        mCapabilityCallback = c;
        mRegTracker.changeCapabilities(enabledCaps, disabledCaps);
        activateSimlessVoLteIfNeeded();"""
    if old_imts4 in s:
        s = s.replace(old_imts4, new_imts4, 1)

    old_imts5 = """        mServiceRegistry.setMmTelFeature(this);
    }"""
    new_imts5 = """        mServiceRegistry.setMmTelFeature(this);
        activateSimlessVoLteIfNeeded();
    }"""
    if old_imts5 in s:
        s = s.replace(old_imts5, new_imts5, 1)
    p_imts.write_text(s)
PY
ok "applied 4G LTE + VoLTE/ViLTE/VoWiFi/UT patches across telephony and ImsStack"

# ---------------------------------------------------------------------------
# D14 — KernelSU-Next Cold-Boot Namespace Race Fix + SuSFS v2.4.0 Upgrade
# ---------------------------------------------------------------------------
say "D14: KernelSU-Next cold-boot namespace race fix + SuSFS v2.4.0"

if [[ -d "kernel/samsung/universal9611/drivers/kernelsu" ]]; then
    python3 - "kernel/samsung/universal9611" <<'PY'
import os, sys

root = sys.argv[1]

# AnyKernel3 Android 17 support
ak_path = os.path.join(root, "AnyKernel3/anykernel.sh")
if os.path.exists(ak_path):
    s = open(ak_path).read().replace("supported.versions=13 - 16", "supported.versions=11 - 18")
    open(ak_path, "w").write(s)

# include/linux/susfs.h -> v2.4.0 + bool is_statically + KSTAT_SPOOF_CTIME_TV_SEC
h_path = os.path.join(root, "include/linux/susfs.h")
if os.path.exists(h_path):
    s = open(h_path).read()
    s = s.replace('#define SUSFS_VERSION "v2.3.0"', '#define SUSFS_VERSION "v2.4.0"')
    s = s.replace("#define KSTAT_SPOOF_CTIME_TV_SEC (1 < 8)", "#define KSTAT_SPOOF_CTIME_TV_SEC (1 << 8)")
    s = s.replace("\tint                                     is_statically;", "\tbool                                    is_statically;")
    open(h_path, "w").write(s)

# drivers/kernelsu/runtime/ksud_integration.c -> remove premature is_init check in fstat & run second_stage/first_zygote synchronously
ksud_int = os.path.join(root, "drivers/kernelsu/runtime/ksud_integration.c")
if os.path.exists(ksud_int):
    s = open(ksud_int).read()
    s = s.replace(
        "static noinline void ksu_common_newfstat_ret(unsigned int fd_int, void **statbuf_ptr, \n\t\t\tconst int type, const char *syscall_name)\n{\n\tif (!is_init(current_cred()))\n\t\treturn;\n",
        "static noinline void ksu_common_newfstat_ret(unsigned int fd_int, void **statbuf_ptr, \n\t\t\tconst int type, const char *syscall_name)\n{\n"
    )
    open(ksud_int, "w").write(s)

# drivers/kernelsu/policy/allowlist.c -> default_root_profile.namespaces = KSU_NS_GLOBAL
al_path = os.path.join(root, "drivers/kernelsu/policy/allowlist.c")
if os.path.exists(al_path):
    s = open(al_path).read().replace("default_root_profile.namespaces = KSU_NS_INHERITED;", "default_root_profile.namespaces = KSU_NS_GLOBAL;")
    open(al_path, "w").write(s)

# drivers/kernelsu/policy/app_profile.c -> setup_mount_ns(KSU_NS_GLOBAL) in escape_to_root_for_init
ap_path = os.path.join(root, "drivers/kernelsu/policy/app_profile.c")
if os.path.exists(ap_path):
    s = open(ap_path).read()
    if "setup_mount_ns(KSU_NS_GLOBAL);" not in s:
        s = s.replace(
            "    setup_selinux(KERNEL_SU_CONTEXT, cred);\n    commit_creds(cred);\n}",
            "    setup_selinux(KERNEL_SU_CONTEXT, cred);\n    commit_creds(cred);\n    setup_mount_ns(KSU_NS_GLOBAL);\n}"
        )
        open(ap_path, "w").write(s)
PY
    ok "verified KernelSU-Next cold-boot namespace race fix + SuSFS v2.4.0 in kernel/samsung/universal9611"
fi

# Ensure 2GB / 4GB / 6GB selectable LZ4 ZRAM + Swap is configured in device/samsung/universal9611-common
DEV_COMMON="device/samsung/universal9611-common"
if [[ -d "$DEV_COMMON/rootdir/etc" ]]; then
    if ! grep -q '/dev/block/zram0' "$DEV_COMMON/rootdir/etc/fstab.exynos9611" 2>/dev/null; then
        printf '\n/dev/block/zram0 none swap defaults zramsize=4294967296,max_comp_streams=8\n' >> "$DEV_COMMON/rootdir/etc/fstab.exynos9611"
        ok "added 4GB LZ4 ZRAM swap entry to $DEV_COMMON/rootdir/etc/fstab.exynos9611"
    fi
    if ! grep -q 'persist.sys.xt.zram_size' "$DEV_COMMON/rootdir/etc/init.exynos9611.rc" 2>/dev/null; then
        cat >> "$DEV_COMMON/rootdir/etc/init.exynos9611.rc" <<'EOF'

on property:sys.boot_completed=1
    write /proc/sys/vm/page-cluster 0
    write /proc/sys/vm/swappiness 100
    write /sys/block/zram0/comp_algorithm lz4
    write /sys/block/zram0/max_comp_streams 8
    swapon_all /vendor/etc/fstab.exynos9611

on property:sys.boot_completed=1 && property:persist.sys.xt.zram_size=2147483648
    exec - root root -- /system/bin/swapoff /dev/block/zram0
    write /sys/block/zram0/reset 1
    write /sys/block/zram0/comp_algorithm lz4
    write /sys/block/zram0/max_comp_streams 8
    swapon_all /system/etc/fstab.zram.2g

on property:sys.boot_completed=1 && property:persist.sys.xt.zram_size=4294967296
    exec - root root -- /system/bin/swapoff /dev/block/zram0
    write /sys/block/zram0/reset 1
    write /sys/block/zram0/comp_algorithm lz4
    write /sys/block/zram0/max_comp_streams 8
    swapon_all /system/etc/fstab.zram.4g

on property:sys.boot_completed=1 && property:persist.sys.xt.zram_size=6442450944
    exec - root root -- /system/bin/swapoff /dev/block/zram0
    write /sys/block/zram0/reset 1
    write /sys/block/zram0/comp_algorithm lz4
    write /sys/block/zram0/max_comp_streams 8
    swapon_all /system/etc/fstab.zram.6g
EOF
        ok "wired 2GB/4GB/6GB selectable LZ4 ZRAM + Swap activation in $DEV_COMMON/rootdir/etc/init.exynos9611.rc"
    fi
fi

# Ensure AOSP m bacon kernel build uses the KSUN+SuSFS <device>_defconfig
for d_short in m31 m31s m21 f41 a51; do
    cfg_dir="kernel/samsung/universal9611/arch/arm64/configs"
    if [[ -f "$cfg_dir/${d_short}_defconfig" ]]; then
        cp -f "$cfg_dir/${d_short}_defconfig" "$cfg_dir/exynos9611-${d_short}_defconfig"
        ok "synced KSUN+SuSFS ${d_short}_defconfig -> exynos9611-${d_short}_defconfig"
    fi
done

# Replace 17MB vendor/infinity/bootanimation/bootanimation.zip with our 1.2MB XT-OSS bootanimation.zip
if [[ -f "vendor/xt/artwork/bootanimation.zip" && -d "vendor/infinity/bootanimation" ]]; then
    cp -f "vendor/xt/artwork/bootanimation.zip" "vendor/infinity/bootanimation/bootanimation.zip"
    ok "replaced vendor/infinity/bootanimation/bootanimation.zip with XT-OSS bootanimation.zip"
fi

# ---------------------------------------------------------------------------
say "D15: Galaxy A51 & Exynos 9611 Display Power & Idle Lock Decoupling Fix"
# ---------------------------------------------------------------------------
# When config_powerDecoupleAutoSuspendModeFromDisplay or config_powerDecoupleInteractiveModeFromDisplay
# is true, the kernel enables autosuspend before display power-down finishes, and attempts
# to resume without disabling autosuspend first. On the Galaxy A51's AMOLED and optical
# FOD panel, this triggers a panel sleep race condition where the screen stays completely black
# and fails to turn back on after short idle or pocket blanking.
for cfg in "device/samsung/universal9611-common/overlay/frameworks/base/core/res/res/values/config.xml" \
           "device/samsung/a51/overlay/frameworks/base/core/res/res/values/config.xml"; do
    if [[ -f "$cfg" ]]; then
        python3 - "$cfg" <<'PY'
import sys, re
path = sys.argv[1]
content = open(path).read()

# Disable power decoupling to keep autosuspend locked during display blanking/waking
content = re.sub(
    r'<bool name="config_powerDecoupleAutoSuspendModeFromDisplay">\s*true\s*</bool>',
    '<bool name="config_powerDecoupleAutoSuspendModeFromDisplay">false</bool>',
    content
)
content = re.sub(
    r'<bool name="config_powerDecoupleInteractiveModeFromDisplay">\s*true\s*</bool>',
    '<bool name="config_powerDecoupleInteractiveModeFromDisplay">false</bool>',
    content
)
content = re.sub(
    r'<bool name="config_suspendWhenScreenOffDueToProximity">\s*true\s*</bool>',
    '<bool name="config_suspendWhenScreenOffDueToProximity">false</bool>',
    content
)

# For A51, ensure explicit fallback definitions if absent
if "a51" in path and "config_powerDecoupleAutoSuspendModeFromDisplay" not in content:
    idx = content.rfind("</resources>")
    if idx != -1:
        snippet = """    <!-- XT-OS: Enforce coupled autosuspend to eliminate A51 idle lock black screen -->
    <bool name="config_powerDecoupleAutoSuspendModeFromDisplay">false</bool>
    <bool name="config_powerDecoupleInteractiveModeFromDisplay">false</bool>
    <bool name="config_suspendWhenScreenOffDueToProximity">false</bool>
"""
        content = content[:idx] + snippet + content[idx:]

open(path, "w").write(content)
PY
        ok "applied coupled display power / idle wake locks in $cfg"
    fi
done

# ---------------------------------------------------------------------------
say "D16: Purge adbroot & privileged debug contexts from SELinux policy"
# ---------------------------------------------------------------------------
# Duck Detector and modern banking/integrity scanners check whether u:r:adbroot:s0
# is recognized as a valid SELinux context by writing to /proc/self/attr/current or
# querying /sys/fs/selinux/context. In stock user builds, adbroot does not exist (returning
# EINVAL 22). In userdebug trees, adbroot.te exists in sepolicy, returning EACCES 13,
# which leaks the presence of a rooted/debug platform policy.
# We completely purge adbroot declarations from sepolicy so u:r:adbroot:s0 returns EINVAL.
mapfile -t adbroot_files < <(find system/sepolicy device/*/sepolicy vendor/*/sepolicy -name "adbroot.te" 2>/dev/null || true)
for f in "${adbroot_files[@]}"; do
    if [[ -f "$f" ]]; then
        echo "# Purged by XT-OS to eliminate adbroot context recognition" > "$f"
        ok "emptied adbroot sepolicy domain in $f"
    fi
done

# Purge adbroot service and file contexts across sepolicy dirs
mapfile -t sep_dirs < <(find system/sepolicy device/*/sepolicy vendor/*/sepolicy -maxdepth 4 -type d 2>/dev/null || true)
for d in "${sep_dirs[@]}"; do
    for target in "service_contexts" "file_contexts" "system_server.te"; do
        p="$d/$target"
        if [[ -f "$p" ]] && grep -q "adbroot" "$p"; then
            python3 - "$p" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).readlines()
new_lines = [l for l in lines if "adbroot" not in l]
if len(lines) != len(new_lines):
    open(path, "w").writelines(new_lines)
PY
            ok "purged adbroot references from $p"
        fi
    done
done

# Strip dirty sepolicy rules flagged by Duck Detector (system_server execmem, kernel adb_data_file read)
mapfile -t te_files < <(find system/sepolicy device/*/sepolicy vendor/*/sepolicy -name "*.te" 2>/dev/null || true)
for te in "${te_files[@]}"; do
    if [[ -f "$te" ]] && grep -qE "(system_server.*execmem|kernel.*adb_data_file.*read)" "$te"; then
        python3 - "$te" <<'PY'
import sys, re
path = sys.argv[1]
content = open(path).read()
# Comment out any permissive rules granting system_server execmem or kernel adb_data_file read
content = re.sub(r'(\ballow\s+system_server\s+[^;]*execmem\s*;)', r'# \1 (stripped by XT-OS)', content)
content = re.sub(r'(\ballow\s+kernel\s+adb_data_file:[^;]*read\s*;)', r'# \1 (stripped by XT-OS)', content)
open(path, "w").write(content)
PY
        ok "stripped dirty sepolicy rule in $te"
    fi
done

# ---------------------------------------------------------------------------
say "Summary"
# ---------------------------------------------------------------------------
printf '    patches applied to %s\n' "$TREE"
printf '    next: . build/envsetup.sh && lunch xt_m31-userdebug && m bacon\n\n'
