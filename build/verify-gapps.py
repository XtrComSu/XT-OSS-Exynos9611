#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
verify-gapps.py — detect drift between our recorded GApps list and upstream.

WHY THIS EXISTS
---------------
config/xt-gapps.mk is an allowlist: it records exactly what
vendor/pixel/gms/common/common-vendor.mk ships (XT_GAPPS_ALL), states what we keep
(XT_GAPPS_KEEP), and derives the drop by subtraction.

That design is only sound while XT_GAPPS_ALL actually matches upstream. The moment
Google's GApps repo adds a module, the recorded list goes stale and the new module
is silently dropped — which is the SAFE direction (bloat does not creep back), but
it means the ROM quietly contains less than intended, and nobody finds out until
something is missing on a device.

The previous blocklist design failed in the unsafe direction: a new module shipped
silently and there was no way to notice. Two of its entries (`TurboAdapter` vs the
actually-shipped `TurboAdapter_NoBatt`) were already dead when written.

So this script checks the one fact the design depends on: does the tree's
common-vendor.mk still contain exactly the modules we recorded?

  missing  — recorded but no longer upstream. Stale entry; harmless but muddled.
             Fix: remove from XT_GAPPS_ALL.
  new      — upstream but not recorded. IMPORTANT: it is being dropped without
             anyone deciding to drop it. Fix: review it, then either add to
             XT_GAPPS_ALL only (it stays dropped) or to both lists (it ships).

Usage:
    build/verify-gapps.py [--android-root /marimo/xt] [--repo .] [--strict]

Exit: 0 in sync, 1 drift, 2 tree/mkfile not found.
"""

import argparse
import re
import sys
from pathlib import Path

UPSTREAM = "vendor/pixel/gms/common/common-vendor.mk"


def read_mk_list(text: str, var: str):
    """Extract `var := a b c` / `var = \\\n a \\\n b` into a list."""
    m = re.search(
        rf'^{re.escape(var)}\s*:?=\s*((?:.*\\\n)*.*)$',
        text, re.MULTILINE,
    )
    if not m:
        return None
    body = m.group(1).replace("\\\n", " ")
    return [t for t in body.split() if t and not t.startswith("$")]


def upstream_modules(mk_path: Path):
    text = mk_path.read_text(errors="replace").replace("\\\n", " ")
    mods = []
    for m in re.finditer(r"PRODUCT_PACKAGES\s*\+?=\s*([^\n]+)", text):
        for tok in m.group(1).split():
            if tok.startswith("$") or tok == "+=":
                continue
            if tok not in mods:
                mods.append(tok)
    return mods


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--android-root", default="/marimo/xt")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--strict", action="store_true",
                    help="treat 'new upstream module' as failure (default: it is a "
                         "warning, because the new module is dropped, which is safe)")
    args = ap.parse_args()

    repo = Path(args.repo)
    mk = repo / "config/xt-gapps.mk"
    up = Path(args.android_root) / UPSTREAM

    if not mk.is_file():
        print(f"not found: {mk}", file=sys.stderr)
        return 2
    if not up.is_file():
        print(f"not found: {up}", file=sys.stderr)
        print("  the GApps vendor tree is not available in this checkout",
              file=sys.stderr)
        return 2

    text = mk.read_text()
    recorded = read_mk_list(text, "XT_GAPPS_ALL")
    keep = read_mk_list(text, "XT_GAPPS_KEEP")
    if recorded is None or keep is None:
        print("could not parse XT_GAPPS_ALL / XT_GAPPS_KEEP from xt-gapps.mk",
              file=sys.stderr)
        return 2

    live = upstream_modules(up)

    recorded_set, keep_set, live_set = set(recorded), set(keep), set(live)

    stale = recorded_set - live_set      # we record, upstream no longer ships
    new = live_set - recorded_set        # upstream ships, we never recorded
    unknown_keep = keep_set - recorded_set   # kept but not in ALL: typo or new

    print(f"recorded XT_GAPPS_ALL : {len(recorded_set)}")
    print(f"recorded XT_GAPPS_KEEP: {len(keep_set)}")
    print(f"live upstream         : {len(live_set)}")
    print(f"effective drop        : {len(live_set - keep_set)}")

    problems = 0
    warnings = 0

    if stale:
        print(f"\nSTALE ({len(stale)}) — recorded but no longer upstream:")
        for m in sorted(stale):
            print(f"  - {m}")
        problems += len(stale)

    if new:
        label = "DRIFT" if args.strict else "WARNING"
        print(f"\n{label} ({len(new)}) — upstream ships these, we never recorded them.")
        print("  They ARE being dropped (allowlist semantics), so nothing unwanted")
        print("  ships — but nobody decided to drop them. Review each, then add to")
        print("  XT_GAPPS_ALL (and to XT_GAPPS_KEEP if it should ship):")
        for m in sorted(new):
            print(f"  + {m}")
        if args.strict:
            problems += len(new)
        else:
            warnings += len(new)

    if unknown_keep:
        print(f"\nUNKNOWN in KEEP ({len(unknown_keep)}) — kept but not in ALL, so they")
        print("  have no effect. Usually a typo:")
        for m in sorted(unknown_keep):
            print(f"  ? {m}")
        problems += len(unknown_keep)

    print()
    if problems:
        print(f"FAIL: {problems} discrepancy/ies.")
        return 1

    if warnings:
        # Exit 0 because the allowlist dropped the new modules (safe direction),
        # but never print "all drops intentional" here: they were not reviewed.
        print(f"PASS with {warnings} warning(s): nothing unwanted ships, but "
              f"{warnings} module(s) are being dropped without an explicit "
              f"decision. Re-run with --strict to fail instead.")
        return 0

    print("OK: recorded list matches upstream exactly; every drop is intentional.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
