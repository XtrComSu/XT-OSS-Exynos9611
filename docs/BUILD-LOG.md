# Build Log — verified findings

Every entry here was verified by running something. Claims are marked:

- **verified** — I ran it and saw the result
- **recorded** — taken from a log, doc, or API response
- **planned** — not yet true

This file is the honest counterpart to the plan documents: the plan says what
should happen, this says what did.

---

## Round 3 — 2026-11-17

### Build in flight

**verified** `m bacon -j20` running detached in `/marimo/xt`, product
`xt_m31-userdebug`, started 11:18 UTC. Progress **19–20% (≈43,800 / 227,736
targets)**, **0 errors**. 113 concurrent `clang++` processes on 20 vCPU, 145 GB of
160 GB RAM available.

Rate measured at 0.95 targets/s over a 20 s window, which extrapolated to a 53-hour
ETA. That number is misleading and I want to be explicit about why: the window fell
during a burst of `external/skia` and composer-AIDL C++ compiles, and ninja target
rate is not a proxy for wall time. A longer background sample was started to get a
usable figure. Early rate was 15.7/s, so the truth is somewhere between.

### The build in flight is stock-looking

**verified** The tree's `vendor/xt` is at commit `6992c8d`, which predates:

| Missing | Consequence |
|---|---|
| `apps/XtThemes`, `XtWidgets`, `XtStatus` | no theme switcher, no widgets, no status app |
| `fonts/Doto-VariableFont.ttf`, `Inter-VariableFont.ttf` | body text is not the Nothing typeface |
| `artwork/bootanimation.zip` | stock boot animation |
| fixed overlays (with `android:category`) | the theme layer is inert |
| GApps allowlist | 33/49 Google modules ship |

**Cause** `repo sync` does not fast-forward an existing clone, and
`bootstrap/00-bootstrap.sh` never refreshed `vendor/xt` at all. **This is now
fixed** — steps 5 and 6 of bootstrap, plus `build/pull-overlay.sh` and
`build/check-tree-fresh.sh` which refuses to build a stale tree.

**Consequence for this round:** the current build cannot be salvaged into the
Nothing ROM. It is a plain-Infinity baseline, which is still useful — it proves the
whole AOSP tree compiles on this box and gives a bootable artifact to compare
against.

---

## Defects found and fixed this round

### Overlays were completely inert (two independent causes)

**verified** `build/verify-overlays.py` against the real framework on the box:

```
XtThemeNothing: 29 resource declarations
OK: every override targets a real framework resource (10 non-public but resolvable)
```

1. They defined `nothing_black`, `nothing_red`, `nothing_surface` — **none of
   which exist in the framework**. An RRO is a *substitution* mechanism; it cannot
   add resources to its target. The APK installed, the overlay "enabled", and
   nothing changed. No build warning, no runtime error.

2. The manifests omitted `android:category`. Without
   `android.theme.customization.system_palette` an overlay is not discoverable by
   ThemePicker and loses arbitration — so a theme could look enabled and still
   render stock.

Negative-tested: the old overlay now exits 1 naming all three dead overrides.

### The GApps trim shipped 33 of 49 modules

**verified** against `vendor/pixel/gms/common/common-vendor.mk`:

```
recorded XT_GAPPS_ALL : 49
recorded XT_GAPPS_KEEP: 27
effective drop        : 22
```

Two of the old blocklist's entries were dead on arrival:
- it dropped `TurboAdapter`, but the module that ships is `TurboAdapter_NoBatt`
  (added conditionally by `products/gms.mk`)
- `GoogleSettingsOverlay` and `libpowerstatshaldataprovider` were never counted

Structurally the blocklist **failed open**: anything upstream added in future would
have shipped silently. Replaced with an allowlist plus `build/verify-gapps.py`,
which was tested in all four states (clean / upstream-adds / upstream-removes /
KEEP-typo).

### The kernel branch had no SUSFS

**verified** via the GitHub API: `lineage-24.0-KSUN` (468ab83) has KernelSU-Next
and **no SUSFS at all** — no `fs/susfs.c`, no `include/linux/susfs.h`, no
`CONFIG_KSU_SUSFS`. The manifest now pins `ksun-susfs` (73420a8), which has
`fs/susfs.c` at 58229 B and a defconfig already setting `CONFIG_KSU_SUSFS=y` plus
the `SUS_PATH` / `SUS_MOUNT` / `SUS_KSTAT` / `TRY_UMOUNT` options.

The branches diverged (142 ahead, 7 behind). The 7 missing commits are build
tooling only — AnyKernel3, `build_kernel`, DTB/DTBO support — none used by an AOSP
build, which reads `TARGET_KERNEL_CONFIG`.

### The KernelSU submodule arrived empty

**verified** On the old branch, `drivers/kernelsu` is a symlink to
`../KernelSU-Next/kernel` and `KernelSU-Next/` was **empty** after `repo sync`
(0 files), while `drivers/Kconfig` still contained
`source "drivers/kernelsu/Kconfig"`. Kconfig pointed at a nonexistent file, so the
kernel could not be configured at all.

Fixed by initialising the submodule (verified: 62 files, Kconfig present). The
switch to `ksun-susfs` removes the dependency entirely.

### A comment broke the manifest

**verified** Writing `git submodule update --init` inside an XML comment made the
manifest unparseable — XML forbids `--` in comments. `repo` would refuse the file
outright and the error says nothing about hyphens. `build/verify-manifest.py` now
detects this by name.

Writing that guard exposed a mistake in my own check: the first version rejected
every project without an explicit `revision`, flagging 23 of 25. That rule is wrong
— this is a *local* manifest merged with ProjectInfinity-X's, which supplies
`<default revision>`. Confirmed empirically by `repo sync` having completed rc=0
with exactly this manifest.

---

## Guards added (all negative-tested)

| Script | Catches | Tested |
|---|---|---|
| `verify-overlays.py` | RRO overriding a nonexistent resource | old overlay → exit 1, new → 0 |
| `verify-gapps.py` | upstream drift, stale records, KEEP typos | all 4 states |
| `verify-manifest.py` | XML `--` trap, dup paths, bad remotes | both traps → exit 1 |
| `verify-release.sh` | test-keys, no boot.img, no overlays, no SUSFS | 3 out-dirs, 1→0 |
| `check-tree-fresh.sh` | stale `vendor/xt`, missing assets | stale → exit 1, real clone → 0 |

A guard never seen to fail is not a guard, so each was deliberately made to fail
before being trusted. That process caught two real bugs *in the guards themselves*:
`verify-gapps.py` printed a warning and then still claimed "every drop is
intentional", and `verify-manifest.py` mis-implemented repo's revision resolution.

---

## Still open

- **verified** No flashable zip yet. Build at ~20%.
- The current build is a stock-looking baseline and will be superseded.
- Kernel swap to `ksun-susfs` must happen in the tree; only the kernel and boot
  image are invalidated, so it is incremental rather than a full rebuild.
- Release keys must be generated on the box before any publishable build
  (`build/gen-release-keys.sh`, output gitignored).
- `MemAvailable` target of 3–4 GB is **planned**, not measured. Nothing in this
  round measured it on hardware; `XtStatus` exists to make that measurable.

---

## Round 3, continued — the GApps trim was never working

### The finding

**verified** `get_build_var PRODUCT_PACKAGES` on the box contained `Velvet=1`,
`LatinIMEGooglePrebuilt=1`, `TurboAdapter_NoBatt=1` — every module the allowlist
claimed to drop was present. The build would have shipped **all 49** Google modules
instead of the intended 30.

The config looked right:

```make
XT_GAPPS_DROP := $(filter-out $(XT_GAPPS_KEEP),$(XT_GAPPS_ALL))
PRODUCT_PACKAGES := $(filter-out $(XT_GAPPS_DROP),$(PRODUCT_PACKAGES))
```

### Why it cannot work

`$(call inherit-product, X)` **does not include X**. It appends a literal marker
word `@inherit:<path>` to each product variable. Those markers are expanded much
later, by `import-nodes` (`build/make/core/node_fns.mk:246`).

So at the moment a product makefile runs, `PRODUCT_PACKAGES` holds only what has
been added *directly* — never the inherited modules. Instrumenting the file at the
exact filter point:

```
XTPROBE drop_count=22           the drop list was correct
XTPROBE velvet_in_drop=1        Velvet was in it
XTPROBE pp_word_count=4         PRODUCT_PACKAGES held FOUR words
XTPROBE inherit_markers=0       not even markers yet
```

Filtering a 22-name list out of a 4-word variable removes nothing. Silently,
permanently, with no warning.

AOSP has **no** post-inherit removal hook — checked `product.mk`,
`product_config.mk`, `node_fns.mk`. Subtraction is not expressible. The only
workable approach is to never add the modules.

### The trap inside the fix

`WITH_GAPPS` in Infinity X does **not** mean "include GApps". `common.mk:289` uses
it to inherit three bundles: `gms.mk`, `themepicker.mk`, `sounds.mk`. Setting it
`false` would have silently removed the theme picker and the Pixel sound set.

The fix therefore sets it false **and** inherits `themepicker.mk` + `sounds.mk`
explicitly, then adds the allowlist. `gms.mk` also carried ~24 `setupwizard.feature.*`
properties; those are reproduced verbatim, because dropping them gives a visibly
reduced first-boot flow.

`version.mk:32` uses `WITH_GAPPS` only to name the zip (GAPPS vs VANILLA) and
`BoardConfigReservedSize.mk:8` only for partition sizing — neither changes what
installs, so the product keeps its identity.

### Verified after the fix

**verified** `lunch rc=0`, module count **1209 → 1175**:

| Check | Result |
|---|---|
| `Velvet`, `LatinIMEGooglePrebuilt`, `GoogleSettingsOverlay`, `Chrome`, `WellbeingPrebuilt`, `AndroidAutoStubPrebuilt` | **0** each |
| `Phonesky`, `PrebuiltGmsCoreVic_*`, `WebViewGoogle-Stub`, `TrichromeLibrary-Stub`, `SetupWizardPrebuilt_versioned`, `GoogleServicesFramework`, `talkback`, `GoogleTTS`, `GoogleContacts` | **1** each |
| `FrameworkOverlayThemePicker`, `FrameworkPixelSounds` | **1** each — not lost |
| `XtThemes`, `XtWidgets`, `XtStatus` | **1** each |

### The lesson that generalises

`build/verify-gapps.py` compares two static lists and reported **OK the whole
time**. A static checker cannot see make-time variable state. Only an artifact
check — the staged product tree, or `get_build_var` — catches this class of bug.

Same shape as the inert overlays and the stale `vendor/xt`: **the build is green,
the files look correct, and the effect is absent.** Three instances of one pattern
in this project is enough to treat "did the artifact actually change?" as a required
check on every mechanism, not an optional one.

New guard: `xt-gapps.mk` now `$(error)`s at parse time if `WITH_GAPPS` is true
alongside the allowlist, because that combination would re-add all 49 on top of the
30. Static review cannot catch that; a hard build failure can.

---

## Why the build takes 16 hours (measured, not guessed)

### The number

**verified** From `make.log` birth over the full elapsed window, **verified**:

```
5,379 / 231,877 targets in 23 min
3.90 targets/s sustained
=> full build 16.5 h, remaining 16.1 h
```

An earlier estimate of 3–3.5 h was wrong by roughly 5×. It came from a 20-second
sample that happened to land inside a burst of `external/skia` C++ compiles, where
target throughput is high because the targets are small. Extrapolating short
windows across a 232k-target DAG is not sound; only elapsed-time averaging is.

### The cause

**verified** The build box is a **gVisor sandbox**, not a normal VM:

```
/proc/version : Linux version 4.19.0-gvisor #1 SMP ...
dmesg         : [0.000000] Starting gVisor...
                [0.356454] Generating random numbers by fair dice roll...
dmesg         : [0.436085] Moving files to filing cabinet...
```

Every syscall is intercepted by gVisor's Sentry, a userspace kernel. The CPU
breakdown shows the cost directly:

| | share |
|---|---|
| user | 56.7% |
| **system** | **35.2%** |
| idle | 8.0% |
| iowait | 0.0% |
| steal | 0.0% |

**35% of CPU time is spent in syscall emulation, not compiling.** A C++ compile is
fork/exec/read/write/mmap heavy, so this is the worst possible workload for it.

### The fix that looked obvious and was refuted

Raising `-j` above 20 was the first instinct. **The measurement refutes it:** idle is
8% and steal is 0%, so the 20 cores are already 19.8/20 occupied. The 35% system
time is not idle gaps waiting to be filled — it is real core-time consumed on
emulation. More jobs would add contention, not throughput.

### The fix that was available and deliberately rejected

`WITH_DEXPREOPT` is unset, so it defaults to `true` (AOSP's `dex_preopt.mk:16`),
meaning every app is AOT-compiled at build time. Restricting it to
boot-image-only would save an estimated 2–3 h.

**Rejected by user decision.** The device is an Exynos 9611 with 6 GB RAM, and the
stated goal is 3–4 GB free plus efficient idle. Deferring dexpreopt to first launch
would push that compilation onto the phone at the worst possible moment, trading
build time for exactly the on-device behaviour this ROM exists to avoid. A slower
build once is the correct trade.

### What actually makes restarts cheap

**verified** The build is resumable by design: Soong+siso keep a dependency log per
output, so a re-run skips unchanged targets and continues from the frontier. This is
why losing an entire box cost only compilation time, never analysis — and why
copying 17 GB of objects off-host is the wrong protection. There is no persistent
volume anyway: `/marimo` is on the overlay root and the only 9p mounts are
single-file binds.

`build/resume-build.sh` wraps this, and refuses to resume onto a drifted tree
because objects from the wrong tree are worse than no objects.

**ccache status:** wired in (`max_size = 40 GB`, compression on) but **useless for
the first build** — 0 hits / 1,451 misses, since the cache starts empty. Its value
is on the second build: config-only changes should drop from ~16 h to single digits.
