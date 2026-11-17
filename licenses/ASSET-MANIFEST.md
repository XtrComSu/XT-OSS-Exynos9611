# Asset Licence Manifest

Every asset that ships inside the ROM zip, with provenance. This file must be
included in any release artifact.

| Asset | Upstream | Licence | Bundled | Notes |
|---|---|---|---|---|
| Doto (variable) | Google Fonts | OFL 1.1 | planned | closest legitimate dot-matrix match to Ndot |
| Inter (variable) | rsms/inter | OFL 1.1 | planned | body text |
| JetBrains Mono | JetBrains | OFL 1.1 | planned | technical readouts, optional |
| Lawnicons | LawnchairLauncher | Apache-2.0 | planned | monochrome icon pack |
| Boot animation | ours | own work | planned | 1080x2400, dot-matrix |
| Charging animation | ours | own work | planned | |
| UI sounds | ours (synthesised) | own work | planned | |
| Wallpapers | ours / CC0 | own / CC0 | planned | provenance recorded per file |
| Dot glyphs | ours | own work | planned | drawn on a 6x10 dot grid |
| Widget app | ours | Apache-2.0 | planned | |
| Theme RROs | ours | Apache-2.0 | yes | this repo |

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
