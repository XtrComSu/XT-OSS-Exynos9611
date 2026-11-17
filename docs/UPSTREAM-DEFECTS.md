# Upstream defects found by building, not by reading

Everything here was discovered by syncing Infinity X 4.2 (branch `17`, AOSP
`android-17.0.0_r1`) and running `lunch xt_m31-userdebug && m bacon` on a
186 GB tree. None of it was visible from reading manifests or docs.

If Infinity X fixes any of these upstream, the corresponding delta in
`build/patch-trees.sh` becomes unnecessary — but the deltas are written so they
degrade to no-ops rather than conflicting.

---

## D5 — `INFINITY_BUILD` is never set for non-`infinity_*` products

**Severity: build-blocking, and the root cause of three other symptoms.**

`build/envsetup.sh`, inside `lunch()`:

```bash
if (echo -n $1 | grep -q -e "^infinity_") ; then
  INFINITY_BUILD=$(echo -n $product | sed -e 's/^infinity_//g')
else
  INFINITY_BUILD=
fi
```

`build/make/core/config.mk:501` then gates the entire Infinity configuration
chain on that variable being non-empty:

```make
ifneq ($(INFINITY_BUILD),)
include vendor/infinity/config/BoardConfigLineage.mk
endif
```

Any product *not* named `infinity_<device>` therefore never includes
`BoardConfigLineage.mk`, and with it never includes `BoardConfigKernel.mk`.

Consequences, all observed:

| symptom | real cause |
|---|---|
| `get_build_var KERNEL_MAKE_CMD` → empty | `KERNEL_MAKE_CMD` is defined in `BoardConfigKernel.mk`, which never ran |
| `get_build_var KERNEL_BUILD_OUT_PREFIX` → empty | same |
| Soong: `module "generated_kernel_includes": cmd: unknown variable '$(KERNEL_BUILD_OUT_PREFIX)'` | the variable is exported to Soong via `EXPORT_TO_SOONG` in `BoardConfigSoong.mk`, which also never ran — so it stayed unset and Soong rejected the reference |
| `get_build_var TARGET_KERNEL_CLANG_PATH` → `/prebuilts/...` | `BUILD_TOP` was empty, making the path collapse |

**Why this is easy to misdiagnose:** the Soong error names
`KERNEL_BUILD_OUT_PREFIX`, and that variable *is* defined at
`BoardConfigKernel.mk:203`. So the natural conclusion — "the file is wrong" — is
false; the file simply never loads. The include guard is two files away.

**Fix:** add an `elif` branch for `xt_*`, stripping the prefix so
`INFINITY_BUILD` holds the bare device name (`m31`), identical to what
`infinity_m31` produces.

**Upstream fix would be:** derive `INFINITY_BUILD` from whether the product
actually inherits `vendor/infinity`, rather than from a name prefix.

---

## D3a — `BUILD_TOP` is used but never assigned

`$(BUILD_TOP)` appears in `vendor/infinity/config/BoardConfigKernel.mk` (lines
93, 145) and `vendor/infinity/build/tasks/kernel.mk` (lines 162, 282, 297), but
`grep -rn 'BUILD_TOP *:='` across the whole tree returns nothing.

With it empty, `$(BUILD_TOP)/prebuilts/clang/...` collapses to
`/prebuilts/clang/...`. The build then reports a missing toolchain — a symptom
that points at the toolchain, not at an unset variable.

**Fix:** `BUILD_TOP := $(abspath .)` in the device `BoardConfigCommon.mk`, guarded
by `ifeq ($(BUILD_TOP),)` so it becomes a no-op if upstream ever defines it.

**Note on AOSP history:** `ANDROID_BUILD_TOP` is the canonical variable and is
explicitly marked obsolete (`config.mk:55`). `BUILD_TOP` is a Lineage/Infinity
invention that was never wired up.

---

## D3b — the kernel clang path defaults to a directory that does not exist

`BoardConfigKernel.mk:93`:

```make
TARGET_KERNEL_CLANG_PATH ?= $(BUILD_TOP)/prebuilts/clang/host/$(HOST_PREBUILT_TAG)/$(KERNEL_CLANG_VERSION)
```

But the 4.14-era prebuilt shipped by the Infinity X manifest lives at
`prebuilts/clang/kernel/linux-x86/clang-r416183b`. Verified on the synced tree:

- `prebuilts/clang/host/linux-x86` — **absent**
- `prebuilts/clang/kernel/linux-x86/clang-r416183b` — present

Setting only `TARGET_KERNEL_CLANG_VERSION := r416183b` therefore still points at
a nonexistent directory. Both the version *and* the full path must be set.

**Fix:** set `TARGET_KERNEL_CLANG_PATH` explicitly, and assert the compiler
binary is executable afterwards.

---

## D-nonbug — `LLVM_IAS=1` is correct for this kernel, despite being 4.14

The instinct on a 4.14 kernel is to force `LLVM_IAS=0` / `-no-integrated-as`.
That would have been wrong here.

`kernel/samsung/universal9611/Makefile:558`:

```make
LLVM_IAS ?= 1
ifeq ($(LLVM_IAS),0)
CLANG_FLAGS += -no-integrated-as
GCC_TOOLCHAIN_DIR := $(dir $(shell which $(CROSS_COMPILE)elfedit))
CLANG_FLAGS += --prefix=$(GCC_TOOLCHAIN_DIR)$(notdir $(CROSS_COMPILE))
endif
```

LLVM support has been backported into this kernel, so Infinity X's unconditional
`KERNEL_MAKE_FLAGS += LLVM=1 LLVM_IAS=1` is correct and needs no override.

Recorded here because "fixing" it would have introduced a bug.

---

## S1 — a root `soong_namespace` breaks the bootstrap

Self-inflicted, kept as a warning.

Declaring

```
soong_namespace { imports: ["android"] }
```

at `vendor/xt/Android.bp` fails with:

```
error: vendor/xt/Android.bp:11:1: module "soong_namespace":
namespace android does not exist
```

The implicit default namespace already covers the whole tree, so `vendor/xt`
needs no declaration at all. Declaring one *replaces* the default with a new
namespace that then tries to import a namespace named `android` — which is not
the default namespace's name. Deleting the file is the fix.

Lesson: `soong_namespace` is for *isolating* a tree, not for making one visible.

---

## G1 — the GApps trim list was invented, and named modules that do not exist

The first draft of `config/xt-gapps.mk` dropped `GoogleMaps`, `GoogleGmail`,
`GooglePhotos`, `GoogleDrive`, `GoogleKeep`, `GoogleFilesGo`, `GoogleChrome`,
`PixelLauncher`, `PixelTips` and others.

None of those modules exist in the GApps repo Infinity X actually uses
(`tejas101k/proprietary_vendor_pixel_gms`, branch `seventeen`). That GApps build
ships **no** Maps/Gmail/Photos/Drive/YouTube at all — the only browser is
`Chrome-Stub`. `PRODUCT_PACKAGES := $(filter-out ...)` on nonexistent names is a
silent no-op, so the "trim" would have removed nothing while looking correct.

The verified list is now 16 real module names, each machine-checked against
`common/common-vendor.mk`. Two entries that look disposable are not:
`WebViewGoogle-Stub` and `TrichromeLibrary-Stub` are load-bearing — removing
them gives blank in-app web views that read as application bugs rather than as a
ROM defect.

**Method note:** this is the failure mode to watch for with `filter-out`. It
never errors. Verify every dropped name against the source that defines it.
