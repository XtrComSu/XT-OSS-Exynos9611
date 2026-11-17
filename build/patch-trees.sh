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
say "Summary"
# ---------------------------------------------------------------------------
printf '    patches applied to %s\n' "$TREE"
printf '    next: . build/envsetup.sh && lunch xt_m31-userdebug && m bacon\n\n'
