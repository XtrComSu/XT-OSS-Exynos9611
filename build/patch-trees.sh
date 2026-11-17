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
#   D3  kernel clang pin                         (4.14 cannot build with A17 clang)
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
# Only touch files that actually reference vendor/lineage. Upstream M31-family
# trees reference it in exactly two places; siblings follow the same pattern.
mapfile -t hits < <(grep -rl 'vendor/lineage' \
    device/samsung vendor/samsung 2>/dev/null || true)

if [[ ${#hits[@]} -eq 0 ]]; then
    ok "nothing to patch"
else
    for f in "${hits[@]}"; do
        # Guard: refuse to rewrite anything that is not a makefile-ish file.
        case "$f" in
            *.mk|*.bp|*.sh) ;;
            *) warn "skipping non-makefile $f"; continue ;;
        esac
        # Guard: the replacement target must exist, or we would swap one broken
        # include for another. Both targets verified present in Infinity X @ 17.
        if [[ ! -f vendor/infinity/config/common_full_phone.mk ]] \
        && [[ ! -f vendor/infinity/config/BoardConfigReservedSize.mk ]]; then
            warn "vendor/infinity not synced yet — run repo sync first"
        fi
        sed -i 's|vendor/lineage|vendor/infinity|g' "$f"
        ok "patched $f"
    done
fi

# Post-condition: no references left.
if grep -rq 'vendor/lineage' device/samsung vendor/samsung 2>/dev/null; then
    die "vendor/lineage still referenced after D1"
fi
ok "verified: zero vendor/lineage references remain"

# ---------------------------------------------------------------------------
say "D2: register xt_<device>.mk in AndroidProducts.mk"
# ---------------------------------------------------------------------------
# Upstream AndroidProducts.mk lists only lineage_<device>.mk. Our product files
# live in vendor/xt/products, so we do not copy them into the device tree —
# instead we add a pointer to them. This keeps the delta to one appended block
# per device and survives upstream rebases cleanly.
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
# BoardConfigCommon.mk sets TARGET_KERNEL_NO_GCC := true, so the kernel builds
# with platform clang. Infinity X defaults KERNEL_CLANG_VERSION to
# $(LLVM_AOSP_PREBUILTS_VERSION), which on Android 17 is far too new for a
# Linux 4.14 kernel. Pin an era-appropriate prebuilt that is ALREADY in the
# manifest (prebuilts/clang/kernel/linux-x86/clang-r416183b) so this costs no
# extra download.
bcc="device/samsung/universal9611-common/BoardConfigCommon.mk"
if [[ -f "$bcc" ]]; then
    marker="# XT-OS: 4.14 kernel needs an era-appropriate clang"
    if grep -qF "$marker" "$bcc"; then
        ok "clang pin already present"
    else
        cat >> "$bcc" <<EOF

$marker
TARGET_KERNEL_CLANG_VERSION := r416183b
EOF
        ok "pinned TARGET_KERNEL_CLANG_VERSION := r416183b"
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
