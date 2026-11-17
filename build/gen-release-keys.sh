#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# gen-release-keys.sh — create the signing keys for a release build.
#
# WHY THIS IS A SCRIPT AND NOT A FOLDER OF KEYS
# ---------------------------------------------
# A ROM signed with AOSP's public `test-keys` cannot boot with secure props, and
# `ro.build.tags=test-keys` is on this project's never-ship list. A real release
# needs its own keys.
#
# Those keys must NEVER be committed. If they leak, anyone can sign an OTA that the
# device will accept as genuine — it is the difference between "someone built a
# ROM" and "someone can backdoor every install of this ROM". So:
#
#   * this script is in git (reviewable, reproducible)
#   * its output is gitignored (keys/ is in .gitignore)
#   * the keys live on the build machine and in a backup the user controls
#
# The AOSP key set is not one key. Each has a distinct job:
#
#   releasekey    default for most system apps (PRODUCT_DEFAULT_DEV_CERTIFICATE)
#   platform      apps holding signature-level permissions — the most powerful one
#   shared        shared-uid apps (the `android.uid.system` family)
#   media         media stack
#   networkstack  connectivity / captive portal
#   sdk_sandbox   SDK runtime sandbox apps
#   bluetooth     BT stack
#   nfc           NFC stack
#   verity        dm-verity metadata signing; its public key goes in the boot image
#
# Sizes follow AOSP's own convention: RSA 2048 for app-signing keys (the platform
# refuses weaker), RSA 4096 for verity.
#
# Usage:
#   build/gen-release-keys.sh [output-dir]
#   build/gen-release-keys.sh --check [output-dir]     # verify an existing set
#
set -euo pipefail

OUT="${1:-keys}"

# A lost releasekey means no future OTA can be installed over this build without a
# full wipe. Warn rather than block, because regenerating deliberately is a valid
# thing to do — silently overwriting is not.
if [[ "${1:-}" == "--check" ]]; then
    OUT="${2:-keys}"
    check=1
    set +e
fi

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v openssl >/dev/null 2>&1 || die "openssl not found"

APPS=(releasekey platform shared media networkstack sdk_sandbox bluetooth nfc)
VERITY=(verity)

# --- --check mode: report what exists, change nothing ----------------------
if [[ "${check:-0}" == "1" ]]; then
    rc=0
    for k in "${APPS[@]}"; do
        if [[ -f "$OUT/$k.pk8" && -f "$OUT/$k.x509.pem" ]]; then
            log "  ok      $k"
        else
            log "  MISSING $k"; rc=1
        fi
    done
    for k in "${VERITY[@]}"; do
        if [[ -f "$OUT/$k.pk8" && -f "$OUT/$k.x509.pem" ]]; then
            log "  ok      $k"
        else
            log "  MISSING $k"; rc=1
        fi
    done
    # The boot image embeds the verity PUBLIC key as PEM.
    if [[ -f "$OUT/verity_key.pem" ]]; then
        log "  ok      verity_key.pem"
    else
        log "  MISSING verity_key.pem"; rc=1
    fi
    exit "$rc"
fi

if [[ -d "$OUT" ]] && [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
    die "$OUT already exists and is not empty.
  Overwriting release keys breaks OTA for every device already on this ROM.
  Move it aside first:
      mv $OUT $OUT.bak.\$(date +%s)"
fi

mkdir -p "$OUT"
chmod 700 "$OUT"

log "Generating release keys in $OUT"
log ""

gen() {
    local name="$1" bits="$2"
    local key="$OUT/$name.key"
    local pem="$OUT/$name.x509.pem"

    # 10000-day validity: a signing key that expires breaks OTA updates for the
    # device's whole service life, and these devices are already years old.
    openssl genrsa -out "$key" "$bits" 2>/dev/null
    openssl req -new -x509 -key "$key" -out "$pem" \
        -days 10000 -subj "/CN=XT-OS $name/" 2>/dev/null
    # PKCS#8 DER, which is the form signapk/apksigner expect from AOSP key sets.
    openssl pkcs8 -topk8 -inform PEM -outform DER -in "$key" \
        -out "$OUT/$name.pk8" -nocrypt 2>/dev/null
    # The original PEM private key is not used by the build and is the most
    # sensitive file here; remove it so only the PKCS#8 form remains.
    rm -f "$key"
    log "  $name  (RSA $bits)"
}

for k in "${APPS[@]}"; do
    gen "$k" 2048
done
for k in "${VERITY[@]}"; do
    gen "$k" 4096
done

# dm-verity expects the public key as a standalone PEM named verity_key.pem.
openssl x509 -in "$OUT/verity.x509.pem" -pubkey -noout > "$OUT/verity_key.pem"
log "  verity_key.pem  (public half, embedded in boot image)"
log ""

# Fingerprints, so two builds can be proven to use the same key set without
# moving the private halves around.
log "Certificate SHA-256 fingerprints (record these in the release notes):"
for f in "$OUT"/*.x509.pem; do
    fp=$(openssl x509 -in "$f" -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//')
    printf '  %-22s %s\n' "$(basename "$f" .x509.pem)" "$fp"
done

log ""
log "Done. Next:"
log "  1. Keep this directory OFF git — keys/ is already in .gitignore."
log "  2. Back it up somewhere you control. Losing it means no OTA for"
log "     devices already installed."
log "  3. Build with:  export PRODUCT_DEFAULT_DEV_CERTIFICATE=vendor/xt/keys/releasekey"
log "     (xt-common.mk sets this automatically when the keys are present)."
