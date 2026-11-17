# Reversibility

The design layer is a **guest, not a host**. If any part of it fails, the ROM must still boot and behave
like stock Infinity X.

## Three levels of "step outside"

### Level 1 — theme switch (instant, no reboot)

`XtThemes` flips RROs with `cmd overlay enable/disable`:

| Mode | Overlays enabled |
|---|---|
| Nothing (default) | `os.theme.nothing` |
| Nothing Light | `os.theme.nothinglight` |
| Material You | `os.theme.monet` |
| Stock Infinity X | `os.theme.stock` (all others disabled) |

No reboot. If the Themes app itself is broken, the same switch is available from a shell:

```bash
cmd overlay list | grep os.theme
cmd overlay enable os.theme.stock
```

### Level 2 — app removal

Every preloaded app is uninstallable by the user:

```bash
pm uninstall --user 0 os.widgets    # or via Settings > Apps
```

Nothing is privileged, nothing is a system-critical component.

### Level 3 — sideload Nothing's own apps

Out of scope for the ROM. Documented as the user's own choice, via the Companion app's links to
upstream sources. Nothing is bundled or mirrored.

## Why RROs and not forked code

| | RRO | Forked SystemUI |
|---|---|---|
| boot-safe on failure | **yes** — bad overlay is a no-op | no — a broken build is a bootloop |
| toggle without reboot | **yes** | no |
| survives upstream rebase | **yes** | conflicts every rebase |
| effort for deep changes | high | low |

We accept the effort cost in exchange for the safety and togglability. That is why **recents and the
notification shade are explicitly out of scope** — they can't be done with RROs, and doing them by fork
would break the promise above.

## Build-time reversibility

If the entire overlay repo is removed from the manifest:

1. `repo sync` gives a pristine upstream tree.
2. `xt_<device>.mk` products disappear; `lineage_<device>.mk` still works... **except** it references
   `vendor/lineage`, which doesn't exist. So a fully pristine revert also needs D1 undone.

That asymmetry is worth knowing: **D1 is the one non-optional delta.** Everything else in this repo
(theme, memory props, GApps trim, apps) can be dropped and the ROM still builds and boots.
