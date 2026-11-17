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
