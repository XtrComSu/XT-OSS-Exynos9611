#!/usr/bin/env bash
# props-audit.sh — pre-release check for ROM-identity leaks and prop coherence.
set -uo pipefail
command -v adb >/dev/null || { echo "adb not on PATH" >&2; exit 1; }
fail=0
chk() {
    local got; got=$(adb shell getprop "$1" 2>/dev/null | tr -d '\r')
    if [[ "$got" == "$2" ]]; then printf 'ok   %-38s %s\n' "$1" "$got"
    else printf 'FAIL %-38s got=%s want=%s\n' "$1" "$got" "$2"; fail=1; fi
}
chk ro.build.type        user
chk ro.build.tags        release-keys
chk ro.debuggable        0
chk ro.secure            1
chk ro.adb.secure        1
chk ro.product.manufacturer samsung

echo "--- leak scan (must be empty) ---"
if adb shell getprop 2>/dev/null | grep -iE 'lineage|infinity|xt[-_]?os|userdebug|test-keys'; then
    echo "FAIL: ROM-identifying strings present"; fail=1
else
    echo "ok   no ROM-identifying strings"
fi

echo "--- selinux ---"
if adb shell getenforce 2>/dev/null | grep -q Enforcing; then echo "ok   Enforcing"
else echo "FAIL not Enforcing"; fail=1; fi

exit $fail
