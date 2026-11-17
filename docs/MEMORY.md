# Memory Efficiency

**Target:** `MemAvailable ≥ 3.0 GB` at idle after cold boot, `≥ 2.5 GB` after 1 h of typical use, on
the 6 GB Galaxy M31, with the Nothing-style layer active.

## The metric

Android fills RAM with cache on purpose. `free -h` reporting "200 MB free" on a healthy device is
normal. So:

| Metric | Use |
|---|---|
| `MemAvailable` from `/proc/meminfo` | **primary** — kernel's own estimate of reclaimable-without-swap |
| PSI `some avg10` in `/proc/pressure/memory` | thrashing detector |
| `pgmajfault` delta over 1 h idle | sustained pressure |
| `dumpsys activity lru` deltas | app-kill churn |

## Baseline facts (verified from upstream trees)

| Fact | Value | Source |
|---|---|---|
| zram size | 50 % of RAM | `configs/init/fstab.exynos9611` |
| zram algorithm | unspecified → kernel default | same |
| lmkd PSI | on, thresholds **unset** | `vendor/samsung/universal9611-common/properties/vendor.prop` |
| `kill_heaviest_task` | true | same |
| background blur | **enabled** | same — `ro.surface_flinger.supports_background_blur=1` |
| panel | 1080×2400 @ 420 dpi | `device.mk` / `BoardConfig` |

## Levers, ranked by effect

### 1. Background blur off — the free win

Upstream enables blur. On Mali-G72 MP3 at 1080p that's a render-target allocation plus a GPU pass per
blurred surface. Nothing's design language is flat monochrome, so turning it off makes the ROM *more*
on-brand while freeing memory and GPU time (est. 150–350 MB).

Set in `config/xt-common.mk`.

### 2. GApps trim — the biggest structural win

300–600 MB of resident memory plus idle wakeups. Every dropped Google package removes a service and
receiver set. See `INTEGRITY.md` §3. **Do not try to tune your way to 3 GB without this.**

### 3. zram algorithm

The fstab sets size but not algorithm. On a 4-core A73:

| Algorithm | Ratio | Speed | Verdict |
|---|---|---|---|
| `lzo` | ~2.1× | fastest | safe |
| **`lz4`** | ~2.3× | very fast | **recommended default** |
| `zstd` | ~3.2× | slower | better ratio, more CPU; power-user option |

Do **not** exceed 50 % zram size — beyond half of RAM you're swapping pages that were cheaper to keep,
and burning CPU to do it. zram writeback to `/data` is the single best "free RAM" lever *if* the kernel
supports it (verify before promising).

### 4. lmkd PSI thresholds

Upstream leaves them at generic defaults. Deliberate values for "6 GB, 4 slow cores, want headroom":

```
ro.lmk.psi_partial_stall_ms=60
ro.lmk.psi_complete_stall_ms=350
ro.lmk.thrashing_limit=40
ro.lmk.thrashing_limit_decay=20
ro.lmk.critical_upgrade=false
```

**Tension to resolve by measurement:** aggressive lmkd raises `MemAvailable` but reloads more apps.
Pick the most aggressive setting that doesn't reload a foreground-adjacent app. Test: Chrome → Camera →
Chrome; if Chrome reloads, back off one step.

### 5. ART filters

`speed-profile` for apps, `speed` for the boot image. A73 cores are slow at JIT, so paying once at boot
is correct. Set in `config/xt-common.mk`.

### 6. True-black default theme

Super AMOLED black pixels are physically off. Default true-black is simultaneously the intended
aesthetic, a battery win (~5–15 % in dark UI), and a GPU fill-cost reduction. Three-way win, zero
trade-off.

## Traps — things that look helpful and aren't

| Trap | Why it's wrong |
|---|---|
| "Free RAM" booster apps | kill apps Android wanted cached → slower reloads, worse battery |
| `drop_caches` on a timer | throws away useful page cache; every read becomes a flash read |
| zram at 75–100 % | swap thrash on 4 slow cores; CPU becomes the bottleneck |
| `swappiness=0` | with zram this prevents the compression that gives you headroom |
| Disabling lmkd | OOM-kills the wrong process at the worst time |
| Removing zygote preloads | makes every app start slower; sharing is a saving, not a cost |
| `performance` governor | thermaI throttle on 9611 makes sustained performance *worse* |
| Magisk "RAM manager" modules | conflict with our lmkd props |

## Measurement protocol

```bash
./build/mem-probe.sh          # reads via adb, fixed output format
```

Run after a clean flash: boot → wait 5 min → probe A. Reboot → wait 5 min → probe B. If A and B differ
by more than 300 MB, something is non-deterministic — find it before tuning.

## Results table

| Step | MemAvailable idle | after 1 h | notes |
|---|---|---|---|
| baseline (stock IX 4.2) | _tbd_ | _tbd_ | must be measured on hardware |
| blur off | _tbd_ | _tbd_ | |
| GApps trimmed | _tbd_ | _tbd_ | |
| zram lz4 | _tbd_ | _tbd_ | |
| lmkd tuned | _tbd_ | _tbd_ | |
| ART filters | _tbd_ | _tbd_ | |
| **final** | **≥ 3.0 GB** | **≥ 2.5 GB** | |

> No number enters this table that did not come from `mem-probe.sh` on real hardware. Estimated numbers
> are worse than blank ones — they get believed.

## 4 GB variant

Scale to `MemAvailable ≥ 1.8 GB` idle / `≥ 1.5 GB` in use, and consider making the widget app optional
there.
