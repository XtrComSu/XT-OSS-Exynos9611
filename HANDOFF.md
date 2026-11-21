# XT-OSS-Exynos9611 — Master Handoff & Architecture Guide

**Version:** 4.2-Damascus  
**Date:** 2026-11-21  
**Status:** **Production Release Complete (`v4.2-xt-os-20261121`)**  
**Maintainer / Author:** XtrCom Team  
**Upstream Base:** Project Infinity-X 4.2 (Android 17 / `lineage-24.0`)  
**Target Hardware Family:** Samsung Exynos 9611 (`universal9611`)  
**Supported Devices:** Galaxy M31 (`SM-M315F`), Galaxy A51 (`SM-A515F`), Galaxy F41 (`SM-F415F`), Galaxy M31s (`SM-M317F`), Galaxy M21 (`SM-M215F`).

---

## 1. Quick Links & Artifacts

- **Production GitHub Release:** [`v4.2-xt-os-20261121`](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/tag/v4.2-xt-os-20261121)
- **Deep-Dive Root Cause & Bugfixes:** [`docs/ISSUES_AND_FIXES_HANDOFF.md`](docs/ISSUES_AND_FIXES_HANDOFF.md)
- **Kernel Repository:** [`XtrComSu/android_kernel_samsung_universal9611`](https://github.com/XtrComSu/android_kernel_samsung_universal9611) (branch: `ksun-susfs`)
- **Overlay & Manifest Repository:** [`XtrComSu/XT-OSS-Exynos9611`](https://github.com/XtrComSu/XT-OSS-Exynos9611) (branch: `main`)

---

## 2. Release Packages & Verification Ledger

All 5 device packages were built with Google Clang 12 (`clang-r416183b`), KernelSU-Next v3.4.2, SuSFS v2.4.0, Minimal GApps, and the red-and-black Nothing-style dot-matrix boot animation:

| Device Model | Codename | File Name | Size (Bytes) | SHA256 Digest | Direct Link |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Galaxy A51** | `a51` (`SM-A515F`) | `XT-OS-4.2-a51-20261121.zip` | 1,858,900,080 | `30d9602c5ef7e75a5e54b1dde9dd47cba2537af9af23f619366a3f66b54a6fa8` | [Download](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/download/v4.2-xt-os-20261121/XT-OS-4.2-a51-20261121.zip) |
| **Galaxy F41** | `f41` (`SM-F415F`) | `XT-OS-4.2-f41-20261121.zip` | 1,703,453,286 | `863a31ad26393491933d1a02e3c0ccd948bac5e33698fdfad556daa24cebb503` | [Download](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/download/v4.2-xt-os-20261121/XT-OS-4.2-f41-20261121.zip) |
| **Galaxy M21** | `m21` (`SM-M215F`) | `XT-OS-4.2-m21-20261121.zip` | 1,704,156,067 | `c2d00534f4824f101d08ba0d9d071e19f88e6b0184f832201ea9ad903a6a4c82` | [Download](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/download/v4.2-xt-os-20261121/XT-OS-4.2-m21-20261121.zip) |
| **Galaxy M31** | `m31` (`SM-M315F`) | `XT-OS-4.2-m31-20261121.zip` | 1,703,885,249 | `c2e87bf8964f66cc16063101fdfdaba0778409b27bfa6cb716a8ae0fca8974dd` | [Download](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/download/v4.2-xt-os-20261121/XT-OS-4.2-m31-20261121.zip) |
| **Galaxy M31s** | `m31s` (`SM-M317F`) | `XT-OS-4.2-m31s-20261121.zip` | 1,703,566,904 | `68ce31c10ff00b930d386430f92c198ba3265c18e088d08bd33865f38d75feb8` | [Download](https://github.com/XtrComSu/XT-OSS-Exynos9611/releases/download/v4.2-xt-os-20261121/XT-OS-4.2-m31s-20261121.zip) |

---

## 3. Key Architecture & Fixes Delivered

### 3.1 Kernel & Root Stack (`ksun-susfs`)
- **Kernel Base:** Linux 4.14.357 (`arch/arm64/configs/exynos9611-<device>_defconfig`).
- **KernelSU-Next v3.4.2 (`33355`):** Directly integrated inside `drivers/kernelsu/` without git submodules. Includes `fs/stat.c` manual hooks for `newfstat` / `fstat64` so `init` reads `KERNEL_SU_RC` without hitting EOF truncation.
- **SuSFS v2.4.0:** Full kernel-level syscall hiding (`fs/susfs.c`, `include/linux/susfs.h`, `CONFIG_KSU_SUSFS=y`, `CMD_SUSFS_SET_SUS_PATH_UID_FILTER`).
- **Cold-Boot Namespace Race Fix:** Fixed asynchronous `task_work_add` race against `first_zygote`. Forced root profile namespaces to `KSU_NS_GLOBAL` so modules mount reliably on cold boot without requiring a soft reboot.
- **Touch-Boost Spinlock Crash Fix:** Corrected `gpex_clock_lock_clock` invocation in `drivers/gpu/arm/exynos/workarounds/gpexwa_interactive_boost.c` by moving sleepable mutex acquisitions outside the IRQ spinlock.
- **A51 Clocks Restored:** Removed CPU/GPU underclock overrides from `arch/arm64/boot/dts/samsung/exynos9611-a51_common.dtsi` and `build/patch-trees.sh` Delta D11, restoring full stock speeds.

### 3.2 Display, Graphics, & SurfaceFlinger
- **ION `/dev/ion` + Gralloc3:** Re-enabled `/dev/ion 0666 system system` in `ueventd.rc` and labeled as `u:object_r:dmabuf_system_heap_device:s0` to resolve Mali G72 EGL allocation crashes on Android 17.
- **Boot Animation:** Built Nothing-style red-and-black dot-matrix animation (`XT-OSS — WELCOME TO THE FUTURE OF FREEDOM`, 265 KB) packaged at `/system/media/bootanimation.zip` and `/product/media/bootanimation.zip`.

### 3.3 UI & Diagnostics (`os.xt.debug` v3.0)
- **Minimalist Aesthetic:** Unified dark `#101010` background, `#181818` raised surfaces, `#F04444` accent red, `#F2F2F2` primary text, `#2C2C2C` dividers, and 10dp rounded corners.
- **Welcome Experience:** Single-screen first-launch wizard (`XtWelcomeActivity`) allowing users to choose 2/4/6 GB ZRAM Swap and toggle 4G LTE / VoLTE with one tap.
- **Vivaldi ANR Shield:** Disables Android 17's aggressive `cached_apps_freezer` to eliminate false 15-second multi-process browser stalls.
- **60 Hz Performance:** UI thread detached from heavy diagnostics; background executor handles memory polling and thermal tracking.

---

## 4. How to Rebuild from Scratch

### 4.1 Prerequisites
- Linux x86_64 build host (Ubuntu 22.04 LTS recommended, 16+ vCPU, 64+ GB RAM, 300+ GB disk).
- Python 3.10+, Java 17+, `repo`, `git`.

### 4.2 Build Steps
```bash
# 1. Clone this overlay repo
git clone https://github.com/XtrComSu/XT-OSS-Exynos9611.git ~/XT-OSS-Exynos9611
cd ~/XT-OSS-Exynos9611

# 2. Bootstrap the AOSP Infinity-X 17 tree
./bootstrap/00-bootstrap.sh ~/xt

# 3. Enter tree and source environment
cd ~/xt
source build/envsetup.sh

# 4. Target any of the 5 models:
lunch xt_m31-userdebug   # or xt_a51, xt_f41, xt_m31s, xt_m21

# 5. Build full signed flashable OTA zip
m bacon
```

---

## 5. Cloud Infrastructure Teardown Ledger

In accordance with strict cost-governance policies:
- All Google Cloud VMs (`xt-build`, `lunaris-gen`, `l4p-uscentral1b`) were decommissioned.
- All 900 GB of persistent disks were permanently deleted.
- Live inspection via `gcloud compute instances list` and `gcloud compute disks list` confirms `Listed 0 items`. Spend is ₹0/hr.
