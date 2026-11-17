# Troubleshooting

Failures in the order you will actually hit them.

---

## Sync

### `repo sync` fails with 404 on a device repo

`lineage.dependencies` resolved against Infinity X's default remote, where those repos don't exist.

**Fix:** make sure `manifest/xt-exynos9611.xml` is installed in the *target tree's*
`.repo/local_manifests/`, then:

```bash
repo sync -c --force-sync --prune -j"$(nproc)"
```

`bootstrap/00-bootstrap.sh` does this for you.

### `repo: command not found`

```bash
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH="$HOME/bin:$PATH"
```

### `repo init` complains about git-lfs

`repo init --git-lfs` requires it:

```bash
sudo apt install git-lfs && git lfs install
```

---

## Patch

### `FATAL vendor/lineage still referenced after D1`

Something outside `device/samsung` / `vendor/samsung` still references it, or a non-makefile file does
(the script intentionally skips `.conf`, `.txt`, etc., and then the post-condition fires).

```bash
grep -rn 'vendor/lineage' device/ vendor/ | grep -v '\.mk:'
```

Patch by hand if it's in a file type D1 doesn't handle, or extend the script's `case` matcher.

### `lunch xt_m31-userdebug` → "product not found"

`AndroidProducts.mk` wasn't patched, or the path in it is wrong.

```bash
grep -A3 'XT-OS overlay products' device/samsung/m31/AndroidProducts.mk
```

The `PRODUCT_MAKEFILES` entry must be **root-relative** (`vendor/xt/products/xt_m31.mk`), not
`$(LOCAL_DIR)/...`-relative.

Also confirm `vendor/xt` is actually synced:

```bash
ls vendor/xt/products/xt_m31.mk
```

---

## Build

### `error: vendor/infinity/config/common_full_phone.mk: No such file`

`vendor/infinity` isn't synced, or you're on the wrong branch. Confirm:

```bash
ls vendor/infinity/config/ | head
repo list | grep infinity
```

### `module "XtThemeNothing" not found`

RROs live in `vendor/xt/overlay/` but must be registered in the Soong namespace that `vendor/xt` exposes.
Check that `vendor/xt/Android.bp` exists with a `soong_namespace` and that `subdirs` includes `overlay`.

If you're iterating and don't need the theme yet, the fastest unblock is to comment out the
`PRODUCT_PACKAGES += XtTheme*` block in `config/xt-common.mk`.

### `module "XtThemes" not found`

The apps don't exist yet — that's expected. They're isolated in `config/xt-assets.mk`, which
`build/gen-assets.sh` regenerates from what's actually present. `xt-common.mk` uses `-include`
(optional), so a missing file is skipped and the build stays green.

```bash
./build/gen-assets.sh    # after adding apps/
```

### Kernel failures

See `DELTAS.md` §D3 fallback ladder. The short version:

1. `TARGET_KERNEL_CLANG_VERSION := r416183b` (default in our patch)
2. `:= r487747c`
3. `TARGET_KERNEL_NO_GCC := false` + AOSP gcc-4.9
4. Ship `TARGET_PREBUILT_KERNEL` and stop fighting it

---

## Flash

### `assert failed: update_dynamic_partitions(...unsparse_super_empty.img)`

Stale dynamic-partition layout. In order:

1. **Format Data** (not wipe) before flashing.
2. Flash the ROM twice in a row without rebooting between.
3. Update TWRP — older builds can't handle `unsparse_super_empty.img`.

### Boots to black, adb alive

Usually SurfaceFlinger / HWC / gralloc:

```bash
adb shell dmesg | grep -iE 'mali|ion|hwc|gralloc'
```

### "System UI isn't responding" after first boot

VNDK/ABI mismatch in a HAL:

```bash
adb logcat -d | grep -i vndk
```

Expect to relax `PRODUCT_ENFORCE_VINTF_MANIFEST` on API-29-era vendor blobs.

### Boot hangs at "Starting services"

SELinux denial loop:

```bash
adb shell dmesg | grep 'avc:'
```

---

## First boot is slow

4–12 minutes is normal. Dexopt of a GApps set on 4× Cortex-A73 is genuinely slow. Don't panic before
12 minutes. Past 15 with no animation change, capture logs from recovery.

---

## Getting help

Capture all of these before asking — they answer 90 % of "it doesn't boot":

```bash
adb logcat -d > logcat.txt
adb shell dmesg > dmesg.txt
adb shell getprop > props.txt
adb shell dumpsys activity > activity.txt
```

And state which device, which `lunch` target, and which phase you're in.
