# Asset Licence Manifest

Every asset that ships inside the ROM zip, with provenance. This file must be
included in any release artifact.

| Asset | Upstream | Licence | Bundled | Notes |
|---|---|---|---|---|
| Doto (variable) | google/fonts `ofl/doto/Doto[ROND,wght].ttf` | OFL 1.1 — `licenses/fonts/OFL-Doto.txt` | **yes** | sha256 `6f4fe7d37853b91df3698daa84cde2dbe1c9695d88c986e6510134910337d426` |
| Inter (variable) | google/fonts `ofl/inter/Inter[opsz,wght].ttf` | OFL 1.1 — `licenses/fonts/OFL-Inter.txt` | **yes** | sha256 `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031` |
| JetBrains Mono | JetBrains | OFL 1.1 | planned | technical readouts, optional |
| Lawnicons | LawnchairLauncher | Apache-2.0 | planned | monochrome icon pack |
| Boot animation | `build/gen-bootanimation.py` | own work (Apache-2.0) | **yes** | 1080x2400 @30fps, 0.46 MB, generated not hand-drawn |
| Charging animation | ours | own work | planned | |
| UI sounds | ours (synthesised) | own work | planned | |
| Wallpapers | ours / CC0 | own / CC0 | planned | provenance recorded per file |
| Dot glyphs | ours | own work | planned | drawn on a 6x10 dot grid |
| Widget app (XtWidgets) | ours | Apache-2.0 | **yes** | dot glyphs drawn in Canvas, no font file |
| Theme RROs | ours | Apache-2.0 | **yes** | this repo |
| Apps (XtThemes/XtStatus) | ours | Apache-2.0 | **yes** | |

## Deliberately NOT bundled

| Asset | Why |
|---|---|
| Ndot / Ndot 57 | Proprietary typeface, Nothing Technology |
| Nothing Launcher / Widgets / Recorder / Gallery / Weather | Proprietary APKs |
| Nothing boot animation, sounds, wallpapers | Proprietary artwork |
| `aashiqhasnat/nothing-styled-icons` | Repo has **no LICENSE file** — all rights reserved. Design reference only. |
| Any bundled keybox | Expire in days; legally someone else's credential |
| Any analytics/telemetry SDK | Project policy |

## Rule

If an asset's licence is unclear, it does not ship. No exceptions, no
"probably fine".
