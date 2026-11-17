#!/usr/bin/env bash
# mem-probe.sh — fixed measurement methodology so before/after are comparable.
set -uo pipefail
command -v adb >/dev/null || { echo "adb not on PATH" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "no device" >&2; exit 1; }

echo "=== $(date -Is) ==="
adb shell 'grep -E "MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree" /proc/meminfo'
echo "--- PSI memory (avg10/avg60/avg300) ---"
adb shell 'cat /proc/pressure/memory 2>/dev/null || echo "(PSI unavailable)"'
echo "--- major faults (cumulative) ---"
adb shell 'grep pgmajfault /proc/vmstat'
echo "--- zram ---"
adb shell 'cat /sys/block/zram0/mm_stat 2>/dev/null | head -1; cat /sys/block/zram0/disksize 2>/dev/null'
echo "--- top RSS ---"
adb shell 'dumpsys meminfo 2>/dev/null | head -30'
echo "--- lru ---"
adb shell 'dumpsys activity lru 2>/dev/null | head -40'
