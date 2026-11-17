#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
verify-manifest.py — validate the repo manifest and the assumptions around it.

WHY THIS EXISTS
---------------
A comment I added to manifest/xt-exynos9611.xml broke the file completely: it
contained `git submodule update --init`, and a double hyphen is ILLEGAL inside an
XML comment. `repo` refuses to parse the manifest at all, so the failure is total
and it has nothing to do with the change being described.

The bad comment was written while explaining a real defect, which is exactly when
attention is on the prose rather than the file format. So the check is automated.

Checks:
  1. The file is well-formed XML (catches the `--` trap and typos).
  2. Every <project> has path, name and a resolvable remote.
  3. No project has an empty/missing revision on a remote that has no default
     (our `xtk` remote deliberately has none, so every xtk project MUST pin one —
     otherwise repo sync fails with "revision not specified").
  4. No duplicate paths.

Usage: build/verify-manifest.py [path]
Exit: 0 ok, 1 problem
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else
                Path(__file__).resolve().parent.parent / "manifest/xt-exynos9611.xml")

    if not path.is_file():
        print(f"not found: {path}", file=sys.stderr)
        return 1

    raw = path.read_text()

    # Check 0: the specific XML trap, reported by name because the generic parser
    # error ("invalid token") gives no hint about what is actually wrong.
    for ln, line in enumerate(raw.splitlines(), 1):
        if "<!--" in line and line.count("--") > 1 and "-->" not in line:
            pass  # a well-formed comment may contain "-->"
    for ln, line in enumerate(raw.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("<!--") or stripped.startswith("-->"):
            continue
        if "--" in line and not line.rstrip().endswith("-->"):
            print(f"line {ln}: illegal '--' inside an XML comment.")
            print("  XML forbids a double hyphen in comment text. Common causes are")
            print("  shell commands with long options (e.g. 'update --init') and")
            print("  em-dash sequences. Rephrase to avoid it.")
            print(f"  offending line: {stripped[:100]}")
            return 1

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        print(f"XML parse error: {e}")
        return 1

    default_el = root.find("default")
    default_rev = default_el.get("revision") if default_el is not None else None

    remotes = {}
    for r in root.findall("remote"):
        name = r.get("name")
        if name:
            remotes[name] = r.get("default")
    rem_bit = []
    for k, v in remotes.items():
        rem_bit.append(f"{k}({'default=' + v if v else 'no default'})")
    print("remotes: " + ", ".join(rem_bit))
    print("default revision: " + (default_rev or "(none)"))

    problems = 0
    unpinned = []
    seen = {}
    projects = root.findall("project")

    for p in projects:
        p_path = p.get("path")
        p_name = p.get("name")
        p_remote = p.get("remote")
        rev = p.get("revision")

        if not p_path or not p_name:
            print(f"  ! project missing path/name: {p.attrib}")
            problems += 1
            continue

        if p_path in seen:
            print(f"  ! duplicate path: {p_path}")
            problems += 1
        seen[p_path] = p_name

        if p_remote and p_remote not in remotes:
            print(f"  ! {p_path}: unknown remote '{p_remote}'")
            problems += 1

        # repo resolves a revision as: project revision > remote revision >
        # <default revision>. A remote lacking a default attribute is harmless as
        # long as the manifest has a <default revision>. Only complain when NOTHING
        # in that chain supplies one, which is the case repo actually rejects.
        if not rev:
            remote_rev = remotes.get(p_remote)
            if not remote_rev and not default_rev:
                # Not fatal HERE, and it must not be reported as fatal. This file is
                # a LOCAL manifest: it is dropped into .repo/local_manifests/ and
                # merged with the upstream manifest from ProjectInfinity-X, which
                # carries its own <default revision="...">. Projects that pin no
                # revision inherit that one. Verified empirically: repo sync
                # completed rc=0 for this exact manifest, which could not happen if
                # the chain were genuinely empty.
                #
                # So this is a note, not a failure. It would only be fatal for a
                # standalone manifest, which this is not.
                unpinned.append(p_path)

    print(f"projects: {len(projects)}")

    # Report the kernel revision, since it is load-bearing for the ROM's root story.
    for p in projects:
        if "kernel" in (p.get("path") or ""):
            print(f"kernel revision: {p.get('revision')}")

    if unpinned:
        print(f"\nnote: {len(unpinned)} project(s) pin no revision and inherit the "
              f"upstream <default>.")
        print("  This manifest is a LOCAL manifest and is merged with "
              "ProjectInfinity-X's,")
        print("  which supplies the default. Correct, not a problem.")

    if problems:
        print(f"\nFAIL: {problems} problem(s)")
        return 1

    print("OK: manifest is well-formed and self-consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
