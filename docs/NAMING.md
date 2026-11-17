# Naming Policy

The ROM should not announce itself through strings a user (or an app) can trivially enumerate.

## Rule

Nothing user-invisible may contain `xt`, `xtos`, `xt-os`, `infinity`, `lineage`, `nothing`, or `dot`.

This is not about hiding from the user — it's about **anti-detection**: a whole class of app heuristic
is "does the package list contain a known custom-ROM package?" Cheap to avoid, so avoid it.

## What it applies to

| Surface | Rule |
|---|---|
| Android package IDs | must not contain the banned tokens |
| `android:label` (visible to user) | plain English: "Themes", "Widgets", "Status" |
| APK file names in `/product` | same as module name, neutral |
| `ro.*` property names we add | prefix with nothing ROM-identifying where avoidable |
| `/system/app`, `/product/app` dir names | neutral |

## What it does NOT apply to

- **Module names in `Android.bp`** (`XtThemeNothing`, `XtWidgets`) — these are build-time identifiers,
  not present on the device as strings an app can query cheaply, and renaming them would make the
  source harder to follow for no gain.
- **The GitHub repo name** (`XT-OSS-Exynos9611`) — that's the project, not the device.
- **`PRODUCT_NAME := xt_m31`** — this *does* surface in `ro.product.name` and build fingerprints, so
  note: it is intentionally kept because the alternative (impersonating `lineage_m31`) is worse, and
  `ro.product.name` alone is not a detection signal that matters when the fingerprint is stock. Revisit
  at the Phase 4 props audit if it shows up in any detector.

## Current package IDs

| App | Package ID | Label |
|---|---|---|
| Themes | `os.themes` | Themes |
| Widgets | `os.widgets` | Widgets |
| Status | `os.status` | Status |
| Theme RROs | `os.theme.nothing`, `.nothinglight`, `.monet`, `.stock` | (invisible) |

Note the RRO package IDs already comply — they carry no branding. The module names do, which is
deliberate and harmless.

## Known deviation

Module name `XtThemeNothing` → package `os.theme.nothing`. Consistent with the rule: module name is
build-time, package name is device-visible.
