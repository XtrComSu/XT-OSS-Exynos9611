# Integrity and GApps

Two goals pulling opposite ways: keep Play Integrity strong, and stop apps detecting that this is a
custom ROM. Plus a hard rule: **never block or discourage custom kernels.**

---

## What verdicts actually exist

| Verdict | Gates | Realistic here? |
|---|---|---|
| `MEETS_BASIC_INTEGRITY` | little; almost everything passes | **yes**, trivially |
| `MEETS_DEVICE_INTEGRITY` | Play Store "certified", most banking apps, RCS | **yes, with work** |
| `MEETS_STRONG_INTEGRITY` | a few strict wallets, some DRM | **only via TrickyStore + valid keybox** |

The M31's TEE attestation is unusable with an unlocked bootloader. No ROM-side work yields genuine
STRONG. Target for v1.0: **DEVICE green, Play Store certified, RCS working.** STRONG is a documented
stretch requiring a user-supplied keybox — never a shipped promise.

---

## Layer 1–2: ROM-side (permanent, free)

| # | Item | Setting |
|---|---|---|
| 1 | Build type | `user` for release; `userdebug` for dev only |
| 2 | Signing | our own release keyset (platform, shared, media, networkstack) |
| 3 | Fingerprint | stock M31 fingerprint (already in `products/xt_m31.mk`) |
| 4 | Security patch | vendor patch must match platform patch |
| 5 | `ro.debuggable` | `0` |
| 6 | `ro.secure` | `1` |
| 7 | `ro.build.tags` | `release-keys` |
| 8 | SELinux | **enforcing** — permissive is a giant tell |
| 9 | AVB | signed vbmeta with our key; `orange` state unavoidable unlocked |

Items 1–2 are non-negotiable. Everything downstream is wasted if they're wrong.

---

## Layer 3: SUSFS (our kernel, ships on)

Built into `XtrComSu/android_kernel_samsung_universal9611@lineage-24.0-KSUN`. Because the kernel is
in-tree we get the native variant, not the GKI LKM workaround.

```
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SUS_SU=y
```

Paths to hide: classic `su` locations, `/data/adb/*` manager artefacts, ROM-identifying app/jar names.

---

## Layer 4–5: deliberately OUTSIDE the zip

PIF-class module and TrickyStore+keybox are **not bundled**. Three reasons:

1. **Keyboxes expire in days.** A observed example was valid for eight days. Baking one in makes the
   ROM dead on arrival.
2. **Distributing a keybox is distributing someone else's device credential.**
3. **User agency.** Ship the capability, not a forced key.

The `XtStatus` app (planned) explains what's green, what's grey, and what the user can do — in plain
language. That page is the product feature.

---

## The "don't block custom kernels" rule, concretely

- ❌ No kernel-signature checks.
- ❌ No props that disable features when a foreign kernel is detected.
- ❌ No integrity logic requiring *our* kernel.
- ✅ Our kernel is the best option (SUSFS built in), not the only one.
- ✅ A foreign kernel gets a dismissible, non-blocking notice for support purposes only.

---

## GApps trim

### Keep (load-bearing)

`GmsCore`, `Phonesky`, `GoogleServicesFramework`, `GsfProxy`, sync adapters, minimal setup wizard,
`CarrierServices` (RCS — verify before touching).

### Drop (installable from Play Store)

Velvet/Google App, Gmail, Maps, YouTube, Photos, Drive, Calendar, Keep, Files, Chrome, Restore, One,
Markup, Pixel Launcher, Tips, Device Personalization, Turbo, Wellbeing, Sound Picker, Wallpaper Picker,
Pixel Themes.

Implemented in `config/xt-gapps.mk` via `PRODUCT_PACKAGES := $(filter-out ...)`. Over-specifying is
safe: filtering a name that isn't present is a no-op.

**One audit pass still owed:** confirm the module names against the actual
`vendor/pixel/gms` + `vendor/infinity` contents after the first sync. Names were derived from the
known Infinity X package set, not read from the synced tree.

---

## Anti-spying

### ROM-identity detection

| Vector | Defence | State |
|---|---|---|
| fingerprint | stock M31 shipped | done |
| `ro.build.tags` / `ro.debuggable` | `release-keys` / `0` on user builds | done |
| app names in `/system` | neutral package IDs and labels | see `NAMING.md` |
| SELinux | enforcing | required |
| Play Integrity | layers 4–5 | user's choice |

### Package enumeration

There is **no** general OS-level "hide my packages" mechanism in AOSP. Any guide claiming otherwise via
`pm` commands is module territory. We do not promise it in the ROM. We do: keep the app count low, no
`QUERY_ALL_PACKAGES` in our own apps, disciplined `<queries>`.

### Telemetry

Our ROM ships **no** analytics, **no** phone-home, **no** OTA check. Android's own privacy controls
(Permission manager, Privacy dashboard, sensors-off) are inherited — verify reachable at the release
gate. Network-level blocking is the user's call.

---

## Props audit (run before every release)

Checks the build is not accidentally leaking ROM identity or incoherent:

```bash
# expected: all ok, and the leak scan empty
adb shell getprop ro.build.type                  # user
adb shell getprop ro.build.tags                  # release-keys
adb shell getprop ro.debuggable                  # 0
adb shell getprop ro.secure                      # 1
adb shell getprop ro.build.fingerprint           # samsung/...M315FXXU3CWA2:user/release-keys
adb shell getenforce                             # Enforcing
adb shell getprop | grep -iE 'lineage|infinity|xt[-_]?os|userdebug|test-keys'   # empty
```

Shipped as `build/props-audit.sh`.
