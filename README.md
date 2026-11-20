# XT-OSS-Exynos9611

Overlay for **Project Infinity X 4.2** (Android 17 / `lineage-24.0`) on **Samsung Exynos 9611**
devices, with a **Nothing-OS-style** visual layer, memory tuning for 6 GB hardware, and an
integrity-first minimal GApps set.

Devices covered: **M31 (SM-M315F)**, **M31s (SM-M317F)**, **F41 (SM-F415F)**, **M21 (SM-M215F)**,
**A51 (SM-A515F)**.

This repo is an **overlay**, not a ROM fork. It adds a manifest, product makefiles, a config layer,
build scripts, and theme overlays on top of unmodified upstream trees. Every change is applied by
script and is reversible.

[Quick start](#quick-start) · [Latest M31 Release](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/latest) · [Verified Build Log](docs/BUILD-LOG.md) · [M31 Sideload Guide](flash/FLASH-M31.md) · [Status](#status)

---

## Why this repo exists

Infinity X ships `vendor/infinity`, **not** `vendor/lineage`, and its manifest default remote is
`github.com/ProjectInfinity-X` — where the M31-family device repos do not exist. A stock
`repo sync` against those trees therefore fails twice:

1. `lineage.dependencies` resolves to repos that 404.
2. `vendor/lineage/...` includes point at a directory that is never synced.

Both are fixed here by pinning every dependency (`manifest/xt-exynos9611.xml`) and
patching the two include paths.

---

## Quick start

```bash
git clone https://github.com/XtrComSu/XT-OSS-Exynos9611
cd XT-OSS-Exynos9611

# full bootstrap into ~/xt: init, manifest, sync, patch, lunch
./bootstrap/00-bootstrap.sh ~/xt

# then build
cd ~/xt
source build/envsetup.sh
lunch xt_m31-userdebug
m bacon
```

Pick your device with `lunch xt_<device>-userdebug` — one of
`xt_m31`, `xt_m31s`, `xt_f41`, `xt_m21`, `xt_a51`.

---

## What's in here

| Path | Purpose |
|---|---|
| `manifest/xt-exynos9611.xml` | pins all 25 projects; the 404 fix |
| `bootstrap/00-bootstrap.sh` | init → sync → patch → lunch, idempotent |
| `build/patch-trees.sh` | the four deltas, verified and re-runnable |
| `products/xt_<device>.mk` | per-device product config (fingerprints read from upstream) |
| `config/xt-common.mk` | memory, ART, integrity props + package list |
| `config/xt-gapps.mk` | GApps trim via `filter-out` |
| `overlay/` | Nothing-style RROs (Nothing / NothingLight / Monet / Stock) |
| `docs/` | deltas, memory, integrity, naming, reversibility, troubleshooting |
| `licenses/ASSET-MANIFEST.md` | provenance for every bundled asset |

---

## The four deltas

Applied by `build/patch-trees.sh`, each with a verification step:

| # | Delta | Why |
|---|---|---|
| **D1** | `vendor/lineage` → `vendor/infinity` | Infinity X has no `vendor/lineage`; verified absent from `default.xml` + both snippets |
| **D2** | register `xt_<device>.mk` in `AndroidProducts.mk` | upstream only lists `lineage_<device>.mk` |
| **D3** | `TARGET_KERNEL_CLANG_VERSION := r416183b` | 4.14 kernel cannot build with A17's default clang; this prebuilt is already in the manifest |
| **D4** | verify `vendor/xt` reachable | our config and products live here |

D1 and D3 are **append/rewrite with post-condition checks** — the script exits non-zero if any
`vendor/lineage` reference survives. Tested against a fixture tree: applies once, is idempotent on
re-run, and fails loudly on residue.

---

## Kernel

Uses `XtrComSu/android_kernel_samsung_universal9611` @ `ksun-susfs` (`lineage-24.0` baseline) — Linux 4.14.357 with
**KernelSU-Next + SUSFS built in**. Defconfig `exynos9611-<device>_defconfig` already exists upstream.

Nothing in this repo gates or blocks a foreign kernel. Flashing a different kernel is supported; SUSFS
hiding simply won't be present if you do.

---

## Licensing

Bundled assets are OFL (Doto, Inter), Apache-2.0 (Lawnicons), or our own work. See
`licenses/ASSET-MANIFEST.md`. Nothing Technology's proprietary assets — Ndot/Ndot 57, Nothing Launcher,
Nothing sounds, Nothing wallpapers — are **not** bundled and never will be.

---

## Status

| Layer | State |
|---|---|
| manifest pinning | **complete**, 25 projects, XML validated (`build/verify-manifest.py`) |
| tree deltas | **complete**, fixture-tested (`build/patch-trees.sh`, [`docs/BUILD-LOG.md`](docs/BUILD-LOG.md)) |
| five product makefiles | **complete**, fingerprints from upstream (`xt_m31`, `xt_m31s`, `xt_f41`, `xt_m21`, `xt_a51`) |
| config layer (memory/ART/integrity) | **complete** |
| GApps allowlist & WebView | **complete**, verified against staged packages (`build/verify-gapps.py`) |
| RRO overlays | **verified** against framework resources (`build/verify-overlays.py`) |
| apps (`XtThemes`, `XtWidgets`, `XtStatus`) | **staged** in `apps/` and included in product packages |
| Galaxy M31 (`SM-M315F`) OTA build | **compiled & published** ([`xt-os-m31-20261119-webview`](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/tag/xt-os-m31-20261119-webview), [`flash/FLASH-M31.md`](flash/FLASH-M31.md)) |
| hardware boot & `M31s`/`F41`/`M21`/`A51` builds | **pending** on-device boot verification and remaining device builds |

The port is not "finished" until a device boots and on-device memory/integrity targets are measured on hardware. Everything above is the verified build and release scaffolding, written to fail loudly rather than silently produce a broken image.
