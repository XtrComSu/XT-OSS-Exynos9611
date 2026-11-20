# Flashing XT-OS on Galaxy M31 (SM-M315F)

Verified against **this tree's own config**, not assumption:

| fact | value | source (verified) |
|---|---|---|
| A/B or A-only | **A-only** | `device/samsung/universal9611-common/common.mk:352` → `AB_OTA_UPDATER := false` |
| Recovery | **separate partition** | `BOARD_RECOVERYIMAGE_PARTITION_SIZE := 71106560` in `device/samsung/m31/BoardConfig.mk:30` |
| Dynamic partitions | **yes** | `BOARD_SUPER_PARTITION_SIZE := 6836715520`, group `samsung_dynamic_partitions` |
| Dynamic members | system, system_ext, product, vendor, odm | `BoardConfigCommon.mk:115-120` |
| AVB | `BOARD_AVB_ENABLE := true`, vbmeta `--algorithm NONE` | `BoardConfigCommon.mk:184-186` |
| OTA asserts | `m31,m31dd,m31nsxx` | `device/samsung/m31/BoardConfig.mk:25` |

Because this is **A-only with a dedicated recovery partition**, the OTA zip ships an
`updater-script` (not `update_engine`), which is exactly what TWRP's *Install →
sideload* path drives. Sideloading is a first-class path here, not a workaround.

---

## 0. Before anything: back up what cannot be re-downloaded

`efs`/`persist` hold your IMEI and radio calibration. Losing them means a phone that
cannot make calls, and no ROM restores them.

In TWRP:

```
Backup → select: EFS, PERSIST, BOOT, DTBO   → Back up to External Storage
adb pull /external_sd/TWRP/BACKUPS/ ./m31-backup/
```

Keep a copy off the phone. Do this **once**, before the first flash.

---

## 1. What you need

- Galaxy M31 (SM-M315F), bootloader already unlocked
- **TWRP recovery** already installed (A-only, with dynamic-partition support)
- The XT-OS zip + its `SHA256SUMS`
- A USB cable that does data, not charge-only
- `adb` + `fastboot` on your computer (`apt install adb fastboot`)

## 2. Verify the download first — this catches a truncated transfer

```bash
sha256sum -c SHA256SUMS
# must print: xt_m31-...zip: OK
```

A partial download flashes as a corrupt system and looks like a hardware fault.

## 3. Boot into TWRP

```bash
adb reboot recovery
```

If adb is not available (system not booting): power off, then hold **Vol-Up +
Vol-Down + Power (with USB connected)** until the recovery splash.

Confirm you are in TWRP, not stock recovery: the UI will be touch-capable and say
*TWRP*.

## 4. Wipe and prepare `/data` for FBE + metadata encryption (CRITICAL)

```
TWRP → Wipe → Format Data → type "yes"
TWRP → Wipe → Advanced Wipe → select: Dalvik, Cache, System, Vendor, Data, Product → Swipe
```

**Important TWRP caveat (verified from device `last_kmsg` + `fs_mgr`):**
Many M31 TWRP builds (including `4.14.113-Grass`) run `make_f2fs` without `-O encrypt`, leaving `/dev/block/by-name/userdata` with `superblock features = 0`. On boot, Android's `fs_mgr` (`system/fs/fs_mgr/fs_mgr.cpp`) mounts that unencrypted F2FS filesystem, skips formatting, and runs `vdc cryptfs encryptFstab ... shouldFormat=false` (`encrypt_inplace`), preserving `features = 0`. `vold` then fails `FS_IOC_ADD_ENCRYPTION_KEY` with `-EOPNOTSUPP`, and `init` reboots to recovery with `enablefilecrypto_failed`.

To make sure Android formats `/data` cleanly inside `dm-default-key` with `make_f2fs -g android` (`encrypt,extra_attr,project_quota,quota_ino,verity,compression,casefold`), do **one** of the following after TWRP Format Data (still in TWRP, before rebooting to System):

- **Option A (Recommended in TWRP — matches LineageOS Recovery's `roots.cpp:320`):** wipe the first 16 MB of `userdata` so `fs_mgr`'s `partition_wiped()` triggers native formatting on first boot:
  ```bash
  adb shell dd if=/dev/zero of=/dev/block/by-name/userdata bs=1M count=16
  adb shell sync
  ```
- **Option B:** Format `/data` using LineageOS / XT-OS recovery (`recovery.img`), which automatically wipes `userdata` when `metadata_encryption` is configured in `recovery.fstab`.

Do **not** wipe `EFS`, `PERSIST`, `Super`, `Boot`, `DTBO`, or `Recovery`.

## 5. Sideload the ROM

In TWRP: **Advanced → ADB Sideload → swipe to start**. Then on the computer:

```bash
adb devices
# expect: <serial>  sideload
adb sideload xt_m31-<tag>.zip
```

You will see the ROM's AOSP updater-script run: it maps the super partition,
resizes `system`/`system_ext`/`product`/`vendor`/`odm`, and writes them. This takes
several minutes. Do not unplug.

Success looks like:

```
Total xfer: 1.00x
```
followed by *"Install completed successfully"* in TWRP. `Total xfer: 1.00x` is the
one to check — anything less means the transfer did not finish.

## 6. Root (optional) — the kernel already has KSUN built in

The boot image ships with **KSU + SUSFS compiled in**. You do not flash anything
extra for the kernel. To install the manager app, after first boot:

```
adb install KernelSU_<ver>.apk
```

SUSFS is active but hidden-by-default; enable the paths you want in the manager.
This is a **user** build signed with XT release keys, so the bootloader warning is
expected and unrelated to root.

## 7. First boot

```
TWRP → Reboot → System
```

**First boot takes 5–15 minutes** — that is ART compiling and the dynamic
partitions settling. It is not a hang. Do not pull the battery.

Expect one automatic reboot partway through. If you see the boot animation loop for
more than ~20 minutes, see Troubleshooting.

## 8. Confirm it actually worked

```bash
adb shell getprop ro.xt.codename           # xt_m31
adb shell getprop ro.build.display.id     # generated build id
adb shell getprop ro.build.type           # user  (not userdebug)
adb shell getprop ro.build.tags           # release-keys  (NOT test-keys)
adb shell getprop ro.xt.version            # our own marker
```

If `ro.build.tags` says `test-keys`, you are running the wrong zip — the release
build is signed with XT keys and should never report `test-keys`.

Check the RAM goal (the whole point of this build):

```bash
adb shell cat /proc/meminfo | grep MemAvailable
```

`MemAvailable` — not `MemFree` — is the number that matters. `MemFree` counts only
completely untouched pages and will look alarmingly small on a healthy Android.
Target is 3–4 GB available on a 6 GB device.

---

## Troubleshooting

**`adb devices` shows nothing in sideload mode**
The USB mode can drop during reboot. Unplug/replug, then `adb kill-server &&
adb start-server`. On Windows the driver is usually the culprit; use Linux if you can.

**"E: failed to verify whole-file signature"**
You are in stock recovery. Reinstall TWRP.

**"This package is for device: m31,m31dd,m31nsxx; this device is ..."**
Your device is an M31 variant not in that list. Do **not** edit the assert unless you
are certain of the codename — flashing another device's system layout is how phones
get bricked. Tell me the codename and I will add it.

**"Not enough space on /super"**
Format Data was skipped, or a previous dynamic partition layout is still live. Repeat
step 4 completely, including Format Data.

**Boot loop after 20 minutes**
Re-enter TWRP and capture the log before guessing:
```
adb shell dmesg > dmesg.txt
adb shell cat /proc/last_kmsg > last_kmsg.txt
adb pull /tmp/recovery.log
```
Send me those three. A kernel that never booted is the most likely cause — this
kernel has `KSUN+SUSFS` and has not yet been proven on hardware, which is exactly
why the fallback boot image exists.

**Emergency: restore a working system**
```
TWRP → Restore → select your backup → Boot, System, Vendor, Data
```
or re-flash the stock firmware with Odin (AP = the One UI `.tar.md5`).

---

## What is NOT in this zip (deliberate)

- **No bootloader or modem firmware.** Flashing those can hard-brick an M31; they are
  updated via Odin with Samsung-signed images only.
- **No GApps beyond Play Store + Play Services + WebView.** No Chrome, no YouTube, no
  Wellbeing — the allowlist was verified to drop 36 of the upstream 49 modules.
- **No keybox, no PIF, no TrickyStore.** Integrity playbooks are installed by you,
  outside this zip, so nothing here pretends to be a certified device.
- **No Nothing OS APKs, fonts or launcher.** Styling is RRO overlays plus Doto/Inter,
  both of which are open-licensed; the Nothing name and assets are not shipped.
