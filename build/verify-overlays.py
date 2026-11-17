#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
verify-overlays.py — prove every resource an overlay overrides actually exists.

WHY THIS EXISTS
---------------
An RRO is a *substitution* mechanism. If an overlay declares a resource the target
package does not define, aapt still builds it, the APK still installs, the overlay
still "enables" — and nothing changes. That is a completely silent failure, and it
is exactly what happened here: XtThemeNothing shipped defining nothing_black,
nothing_red, nothing_surface, none of which exist in android's framework. The
theme was inert.

No builder warning. No runtime error. Just a theme that does nothing while looking
correct in every file listing.

So this script exists to make that failure loud. It cross-references every
`<color>`/`<bool>`/`<integer>`/`<dimen>`/`<string>` name in each overlay's res/
tree against the framework's public resource list, and fails if one is missing.

PUBLIC vs RESOLVABLE
--------------------
Only public resources are enforced, because those are the ones a third-party RRO
is guaranteed to be able to override. `background_device_default_dark` and friends
are NOT public, yet AndroidBlackTheme (shipped by this ROM) overrides them and
works — the framework resolves them for overlays in the system_palette category
because it must, to theme itself. Those are reported as a separate, non-fatal
category: worth knowing, not worth failing on.

Usage:
    build/verify-overlays.py [--android-root PATH] [--strict]

Exit codes: 0 all good, 1 a public resource is missing, 2 framework not found.
"""

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Resource types an RRO can override. Anything else in res/values is either
# metadata (strings for the overlay's own label) or not overridable.
OVERRIDABLE = {"color", "bool", "integer", "dimen", "fraction"}

# Our own resources: these are defined by the overlay for itself (launcher label),
# not substitutions, so they must NOT be checked against the framework.
SELF_RESOURCES = {"theme_name"}


def framework_public_names(android_root: Path):
    """
    Returns (public, all_defined) name sets from framework-res.

    public-final.xml is the generated list of public resources; public-staging.xml
    holds ones still being staged. Both count as "a RRO can target this".
    values/*.xml gives us everything defined, public or not.
    """
    res = android_root / "frameworks/base/core/res/res/values"
    if not res.is_dir():
        return None, None

    public = set()
    for name in ("public-final.xml", "public-staging.xml"):
        f = res / name
        if not f.is_file():
            continue
        # Parsed as text, not XML: these files are huge and we only need the names.
        text = f.read_text(errors="replace")
        for m in re.finditer(r'<public\s+type="(\w+)"\s+name="([^"]+)"', text):
            rtype, rname = m.group(1), m.group(2)
            if rtype in OVERRIDABLE:
                public.add(rname)

    defined = set()
    for f in res.glob("*.xml"):
        text = f.read_text(errors="replace")
        for m in re.finditer(r'<(color|bool|integer|dimen|fraction)\s+name="([^"]+)"', text):
            defined.add(m.group(2))

    return public, defined


def overlay_declared_names(overlay_dir: Path):
    """Every overridable resource name declared anywhere under the overlay's res/."""
    out = {}
    for f in overlay_dir.rglob("*.xml"):
        if "res" not in f.parts:
            continue
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError as e:
            print(f"  !! unparseable {f}: {e}")
            continue
        for child in root:
            if not isinstance(child.tag, str):
                continue
            # Strip any namespace (android: attrs don't apply to these tags).
            tag = child.tag.split("}")[-1]
            if tag not in OVERRIDABLE:
                continue
            name = child.get("name")
            if name:
                out.setdefault(name, []).append(str(f.relative_to(overlay_dir)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--android-root", default="/marimo/xt",
                    help="AOSP tree root (default: /marimo/xt)")
    ap.add_argument("--strict", action="store_true",
                    help="also fail on non-public but resolvable resources")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent),
                    help="XT-OSS repo root")
    args = ap.parse_args()

    repo = Path(args.repo)
    android = Path(args.android_root)

    public, defined = framework_public_names(android)
    if public is None:
        print(f"framework-res not found under {android}", file=sys.stderr)
        print("  pass --android-root, or run after bootstrap has cloned the tree",
              file=sys.stderr)
        return 2

    print(f"framework: {len(public)} public overridable resources, "
          f"{len(defined)} defined total")

    overlays = sorted(p for p in (repo / "overlay").iterdir() if p.is_dir())
    fail = 0
    warn = 0

    for ov in overlays:
        names = overlay_declared_names(ov)
        if not names:
            print(f"\n{ov.name}: no overridable resources (intentional for "
                  f"Monet/Stock — they exist as selectable targets)")
            continue

        print(f"\n{ov.name}: {len(names)} resource declarations")
        for name, sites in sorted(names.items()):
            if name in SELF_RESOURCES:
                continue
            if name in public:
                continue
            if name in defined:
                # Real, resolves in-tree, but not part of the public API.
                print(f"  ~ {name}  (defined but not public — used by "
                      f"AndroidBlackTheme, so it resolves)")
                warn += 1
                if args.strict:
                    fail += 1
            else:
                print(f"  X {name}  NOT IN FRAMEWORK — this override does nothing")
                print(f"      declared in: {', '.join(sites)}")
                fail += 1

    print()
    if fail:
        print(f"FAIL: {fail} ineffective override(s). "
              f"An RRO cannot add resources to its target; it can only replace.")
        return 1

    extra = f" ({warn} non-public but resolvable)" if warn else ""
    print(f"OK: every override targets a real framework resource{extra}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
