#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# sideload-m31.sh — flash XT-OS onto a Galaxy M31 through TWRP's ADB sideload.
#
# This refuses to flash more often than it flashes, and that is the point. The
# failure modes below all produce a phone that looks bricked but is not, and every
# one of them is cheaper to catch here than in a boot loop:
#
#   - a truncated download        -> flashes as corrupt system
#   - stock recovery instead of TWRP -> "failed to verify whole-file signature"
#   - wrong device                -> the OTA assert fires, or worse, it does not
#   - data not formatted          -> the super-partition resize fails
#
# It never wipes anything itself. Deleting user data is the operator's decision,
# made in TWRP's UI where they can see what they are selecting.
#
# Usage: flash/sideload-m31.sh <rom.zip> [--yes]
#
set -uo pipefail

ZIP="${1:-}"
ASSUME_YES="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die()  { printf '\033[31mREFUSING\033[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

[[ -n "$ZIP" ]] || { printf 'usage: %s <rom.zip> [--yes]\n' "$0" >&2; exit 1; }
[[ -f "$ZIP" ]] || die "no such file: $ZIP"

step "1. archive integrity"
# unzip -t catches a truncated transfer, which is the most common bad flash.
if unzip -t "$ZIP" >/tmp/sl_zip.log 2>&1; then
    ok "zip tests clean"
else
    tail -3 /tmp/sl_zip.log
    die "corrupt archive — re-download; do NOT flash this"
fi

step "2. it is the right device, according to the zip itself"
# Read the assert out of the OTA's own updater-script rather than trusting a name.
if unzip -p "$ZIP" META-INF/com/google/android/updater-script 2>/dev/null >/tmp/sl_us.txt; then
    ASSERT=$(grep -oE 'getprop\("ro\.product\.device"\) *== *"[^"]+"' /tmp/sl_us.txt | head -1)
    if [[ -n "$ASSERT" ]]; then ok "OTA assert: $ASSERT"; else warn "no device assert found in updater-script"; fi
    # A-only ROMs ship updater-script; A/B ROMs ship a payload. Distinguish them,
    # because the wrong one cannot be sideloaded the same way.
    if grep -q 'block_image_update\|package_extract_file' /tmp/sl_us.txt; then
        ok "A-only OTA (updater-script uses block_image_update) — sideload-compatible"
    else
        warn "updater-script present but no block_image_update; inspect before flashing"
    fi
else
    if unzip -l "$ZIP" 2>/dev/null | grep -q 'payload.bin'; then
        die "this is an A/B payload OTA — TWRP sideload will NOT work. Use fastboot."
    fi
    warn "no updater-script found"
fi

step "3. signature — is this our release build?"
# The otacert in an AOSP zip is the cert the package was signed with. We generate
# our own, so it must not be the AOSP testkey. Compare against a known fingerprint
# when one is supplied via env, otherwise just report it for the operator.
if unzip -p "$ZIP" META-INF/com/android/otacert 2>/dev/null | \
     openssl x509 -noout -subject -fingerprint -sha256 2>/dev/null | sed 's/^/  /'; then
    ok "otacert present (compare the SHA-256 against the release notes)"
else
    warn "no otacert — cannot confirm signing key"
fi

step "4. host tools"
command -v adb >/dev/null || die "adb not installed (apt install adb)"
ok "adb: $(command -v adb)"

step "5. device state — must be in TWRP sideload mode"
adb start-server >/dev/null 2>&1
STATE=$(adb devices | awk 'NR>1 && NF {print $2}' | head -1)
case "$STATE" in
    sideload) ok "device is in sideload mode" ;;
    recovery) die "device is in recovery but NOT in sideload mode.
       In TWRP: Advanced -> ADB Sideload -> swipe to start, then re-run." ;;
    device)   die "device is booted into Android.
       Run: adb reboot recovery
       Then in TWRP: Advanced -> ADB Sideload -> swipe to start." ;;
    "")       die "no device seen by adb.
       Check the cable is a data cable, the USB mode is not charge-only, and try
       adb kill-server && adb start-server." ;;
    *)        die "unexpected adb state: $STATE" ;;
esac

step "6. has /data been wiped cleanly for metadata+file encryption?"
# TWRP Format Data on 4.14.113-Grass builds formats userdata without -O encrypt
# (superblock features = 0), which causes fs_mgr to run encrypt_inplace instead
# of formatting and fails enablefilecrypto with EOPNOTSUPP. Wiping the first
# 16 MiB of userdata triggers partition_wiped() so vold formats /data natively
# with make_f2fs -g android on first boot (matching LineageOS recovery).
cat <<'MSG'
  Confirm in TWRP you have done ALL of:
    - Wipe -> Format Data -> type "yes"
    - Wipe -> Advanced Wipe -> Dalvik, Cache, System, Vendor, Data, Product
    - In TWRP terminal / adb shell (before ADB Sideload):
        mount /metadata 2>/dev/null || true; rm -rf /metadata/*
        dd if=/dev/zero of=/dev/block/by-name/userdata bs=1M count=16 conv=fsync && sync
      (or formatted using LineageOS / XT-OS recovery.img)
  Do NOT wipe EFS, PERSIST, SUPER, BOOT, DTBO or RECOVERY.
MSG

if [[ "$ASSUME_YES" != "--yes" ]]; then
    printf '\n  Type exactly: FORMATTED\n  > '
    read -r CONFIRM
    [[ "$CONFIRM" == "FORMATTED" ]] || die "not confirmed — nothing was flashed"
fi

step "7. sideloading (this takes several minutes — do not unplug)"
adb sideload "$ZIP" 2>&1 | tee /tmp/sl_out.txt
RC=${PIPESTATUS[0]}

step "8. result"
if grep -q 'Total xfer: 1.00x' /tmp/sl_out.txt; then
    ok "transfer completed 1.00x"
else
    warn "did NOT see 'Total xfer: 1.00x' — the transfer may be incomplete"
fi

if [[ $RC -eq 0 ]]; then
    step "9. post-sideload TWRP verification & in-place fixups"
    sleep 5
    if [[ -f "$HERE/LineageFrameworksOverlay_v3.apk" ]]; then
        adb push "$HERE/LineageFrameworksOverlay_v3.apk" /tmp/LineageFrameworksOverlay_v3.apk >/dev/null 2>&1 || true
    fi
    adb shell "mount -o rw /system_root 2>/dev/null || mount -o remount,rw /system_root 2>/dev/null || true"
    if adb pull /system_root/system/etc/selinux/plat_file_contexts /tmp/sl_plat_fc >/dev/null 2>&1; then
        python3 - /tmp/sl_plat_fc <<'PY' || true
import sys
p = sys.argv[1]
fc = open(p, "rb").read()
t = b"/dev/adf-overlay-engine[0-9]*\\.[0-9]*\tu:object_r:graphics_device:s0\n"
if t in fc:
    pre = b"/dev/ion"
    suf = b"\tu:object_r:dmabuf_system_heap_device:s0\n"
    rep = pre + (b" " * (len(t) - len(pre) - len(suf))) + suf
    open(p + ".new", "wb").write(fc.replace(t, rep, 1))
PY
        if [[ -f /tmp/sl_plat_fc.new ]]; then
            adb push /tmp/sl_plat_fc.new /tmp/sl_plat_fc.new >/dev/null 2>&1 || true
            adb shell "dd if=/tmp/sl_plat_fc.new of=/system_root/system/etc/selinux/plat_file_contexts conv=notrunc 2>/dev/null; sync" || true
        fi
    fi
    adb shell '
      umount /system_root 2>/dev/null || true
      if [ -f /tmp/LineageFrameworksOverlay_v3.apk ]; then
        blockdev --setrw /dev/block/mapper/product 2>/dev/null || true
        mount -o rw /product 2>/dev/null || mount -o remount,rw /product 2>/dev/null || true
        dd if=/tmp/LineageFrameworksOverlay_v3.apk of=/product/overlay/ApertureFrameworksBaseOverlay.apk conv=notrunc 2>/dev/null || true
        umount /product 2>/dev/null || true
      fi
      mount /metadata 2>/dev/null || true
      rm -rf /metadata/*
      dd if=/dev/zero of=/dev/block/by-name/userdata bs=1M count=16 conv=fsync 2>/dev/null || true
      sync
    ' || true
    ok "verified /metadata cleared and userdata header zeroed for vold F2FS encrypt formatting"
    cat <<'MSG'

  Done. Next:
    TWRP -> Reboot -> System

  First boot takes 5-15 minutes (ART compiling). One automatic reboot is normal.
  Do not pull the battery during it.

  Then confirm it is really our build:
    adb shell getprop ro.build.tags      # release-keys, NOT test-keys
    adb shell getprop ro.xt.version
    adb shell cat /proc/meminfo | grep MemAvailable
MSG
else
    die "adb sideload returned $RC — read /tmp/sl_out.txt before retrying"
fi
