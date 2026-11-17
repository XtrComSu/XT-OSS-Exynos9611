# The Four Deltas

Everything this overlay changes about upstream, in one place. If a build breaks, one of these four is
almost always why.

---

## D1 — `vendor/lineage` → `vendor/infinity`

**Evidence.** `vendor/lineage` appears **zero** times in Infinity X's `default.xml`,
`snippets/infinity.xml`, and `snippets/lineage.xml`. The vendor config lives at `vendor/infinity`.
Both replacement targets exist in `vendor_infinity@17`.

**Upstream references** (M31-family trees):

| File | Original line |
|---|---|
| `device/samsung/universal9611-common/BoardConfigCommon.mk` | `include vendor/lineage/config/BoardConfigReservedSize.mk` |
| `device/samsung/<dev>/lineage_<dev>.mk` | `$(call inherit-product, vendor/lineage/config/common_full_phone.mk)` |

**Mechanism.** `patch-trees.sh` greps `device/samsung` and `vendor/samsung` for the string, rewrites
`.mk`/`.bp`/`.sh` files only, and then asserts zero occurrences remain. Non-makefile hits are skipped
with a warning — and because the post-condition still fires, a skipped hit fails the script rather than
slipping through.

**Rationale for rewriting rather than copying files into the tree:** a rewrite is a one-line diff that
survives an upstream rebase. Copying `common_full_phone.mk` into the device tree would drift.

---

## D2 — register `xt_<device>.mk`

**Evidence.** Upstream `AndroidProducts.mk` contains only `$(LOCAL_DIR)/lineage_<device>.mk`.

**Mechanism.** Appends one marked block per device:

```makefile
# --- XT-OS overlay products ---
PRODUCT_MAKEFILES += \
    vendor/xt/products/xt_<device>.mk
```

Two details that matter:

1. **`PRODUCT_MAKEFILES` entries are root-relative**, not `LOCAL_DIR`-relative. An earlier draft used
   `$(LOCAL_DIR)/../../../vendor/...`, which is wrong — `LOCAL_DIR` is `device/samsung/<dev>`, and
   `make` resolves these paths from the tree root.
2. Our product files stay in `vendor/xt/products` rather than being copied into the device tree, so the
   delta remains one appended block.

Idempotent via a marker grep: re-running does not duplicate the block.

---

## D3 — kernel clang pin

**Evidence.** `BoardConfigCommon.mk` sets `TARGET_KERNEL_NO_GCC := true`, so the kernel builds with
platform clang. `vendor_infinity/config/BoardConfigKernel.mk` resolves:

```
KERNEL_CLANG_VERSION := clang-$(TARGET_KERNEL_CLANG_VERSION)   # if set
                     :  $(LLVM_AOSP_PREBUILTS_VERSION)          # default
```

On Android 17 the default is far too new for a **Linux 4.14.357** kernel. Pin:

```makefile
TARGET_KERNEL_CLANG_VERSION := r416183b
```

`prebuilts/clang/kernel/linux-x86/clang-r416183b` is **already in the Infinity X manifest**
(revision `lineage-20.0`, `clone-depth=1`), so this costs no extra download.

### Fallback ladder if the kernel still refuses

1. `TARGET_KERNEL_CLANG_VERSION := r487747c`
2. `TARGET_KERNEL_NO_GCC := false` + AOSP gcc-4.9 aarch64 prebuilts
3. Build the kernel out-of-tree, ship `TARGET_PREBUILT_KERNEL` — decouples kernel pain from ROM pain.
   **Take this exit if Phase 2 stalls past 3 days.**

---

## D4 — overlay reachability

`vendor/xt` must be synced for `$(call inherit-product, vendor/xt/config/xt-common.mk)` to resolve.
Verified by presence check; a warning (not a failure) if absent, because a dry run against a
partially-synced tree should still be informative.

---

## Testing

`patch-trees.sh` was validated against a synthetic fixture mirroring upstream layout:

| Test | Expected | Result |
|---|---|---|
| First run on pristine fixture | patches D1/D2/D3 | pass |
| Second run | no duplicate blocks, no duplicate pin | pass — marker count 1, pin count 1 |
| Reference in a skipped (`.conf`) file | FATAL exit 1 | pass |
| Same file removed | exit 0 | pass |

Reproduce with `build/test-patch.sh` (fixture is generated, real tree untouched).
