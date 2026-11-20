#
# XT-OS common overlay — inherited by every xt_<device>.mk
#
# Everything here is additive on top of vendor/infinity/config/common_full_phone.mk.
# Nothing here forks upstream code; it only sets properties, adds packages, and
# enables RROs. That keeps the whole layer reversible (see docs/REVERSIBILITY.md).
#
# IMPORTANT: this file must stay buildable at every point in the project. Packages
# and copy-files are only added when the module/asset actually exists, because a
# PRODUCT_PACKAGES entry for a nonexistent module is a hard build failure. Optional
# blocks are gated behind `-include` of a generated fragment (see the bottom).
#

# ---------------------------------------------------------------------------
# 1. Identity
#
#    What the device calls itself. Deliberately surgical: PRODUCT_BRAND,
#    PRODUCT_MODEL and PRODUCT_MANUFACTURER stay "samsung"/"SM-M315F" in the
#    device makefile and are NOT overridden here.
#
#    That is not laziness — those three feed ro.product.brand/model/manufacturer,
#    which together with the fingerprint are what Play Integrity and numerous
#    banking apps cross-check. Renaming them to "XT-OS" would make the device
#    claim to be a phone that does not exist, which is a far stronger signal of a
#    custom ROM than any kernel string. The Nothing styling is expressed in the
#    Android version string and the theme layer instead, where it is cosmetic and
#    carries no integrity cost.
#
#    INFINITY_* is kept because it is upstream's own credit mechanism — Infinity X
#    built the base, and passing off their work as entirely ours would be both
#    dishonest and a licence problem.
# ---------------------------------------------------------------------------
XT_VERSION := 1.0
XT_CODENAME := Nothing-styled

PRODUCT_PRODUCT_PROPERTIES += \
    ro.xt.version=$(XT_VERSION) \
    ro.xt.codename=$(XT_CODENAME) \
    ro.xt.base=InfinityX-4.2 \
    ro.xt.base.android=17

# ---------------------------------------------------------------------------
# 2. Efficiency: SurfaceFlinger / blur
#    M31-class hardware (Mali-G72 MP3, 4x A73) pays real RAM + GPU cost for blur,
#    and Nothing's design language does not use it. Off by default; the Themes
#    app can turn it back on at runtime.
# ---------------------------------------------------------------------------
#    Two of these cannot be set here. The device tree already defines
#    ro.surface_flinger.supports_background_blur and debug.sf.auto_latch_unsignaled
#    in properties/vendor.prop, and AOSP's post_process_props.py aborts the build
#    when the same key is assigned twice with DIFFERENT values (identical values
#    are deduped silently, which is why the other props here are harmless).
#    Delta D7 rewrites the device tree's values instead, so there is one source of
#    truth and the efficiency intent below is preserved rather than dropped.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.surface_flinger.max_frame_buffer_acquired_buffers=3 \
    debug.sf.enable_gl_backpressure=1 \
    debug.sf.latch_unsignaled=1 \
    debug.hwui.renderer=skiagl \
    ro.sys.fw.bg_apps_limit=24 \
    ro.hw_timeout_multiplier=2 \
    persist.sys.disable_rescue=true \
    persist.bluetooth.a2dp_offload.disabled=true \
    persist.sys.bt.ldac.abr=true \
    bluetooth.profile.a2dp.source.enabled=true \
    bluetooth.profile.avrcp.target.enabled=true \
    bluetooth.profile.bas.client.enabled=true \
    bluetooth.profile.gatt.enabled=true \
    persist.dbg.volte_avail_ovr=1 \
    persist.dbg.vt_avail_ovr=1 \
    persist.dbg.wfc_avail_ovr=1 \
    persist.dbg.ims_volte_enable=1

# ---------------------------------------------------------------------------
# 3. Efficiency: lmkd (PSI) thresholds
#    Upstream vendor.prop enables PSI but leaves the thresholds at defaults, which
#    are tuned for generic low-RAM devices. These are set for "6 GB, 4 slow cores,
#    keep MemAvailable high" — values from docs/MEMORY.md.
# ---------------------------------------------------------------------------
PRODUCT_PROPERTY_OVERRIDES += \
    ro.lmk.use_psi=true \
    ro.lmk.kill_heaviest_task=true \
    ro.lmk.kill_timeout_ms=100 \
    ro.lmk.psi_partial_stall_ms=60 \
    ro.lmk.psi_complete_stall_ms=350 \
    ro.lmk.thrashing_limit=40 \
    ro.lmk.thrashing_limit_decay=20 \
    ro.lmk.low=1001 \
    ro.lmk.medium=800 \
    ro.lmk.critical=0 \
    ro.lmk.critical_upgrade=false \
    ro.lmk.upgrade_pressure=100

# ---------------------------------------------------------------------------
# 4. Efficiency: ART / dexopt
#    speed-profile for apps, speed for the boot image. A73 cores are slow at JIT,
#    so paying once at boot is the right trade.
# ---------------------------------------------------------------------------
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.dex2oat-filter=speed-profile \
    dalvik.vm.image-dex2oat-filter=speed \
    dalvik.vm.dex2oat-threads=4 \
    dalvik.vm.background-dex2oat-threads=2

# ---------------------------------------------------------------------------
# 5. Integrity: build-surface hygiene
#    ro.adb.secure=1 and ro.secure=1 are already enforced by system/build.prop
#    and init's SetSafetyNetProps(). Setting them again in vendor/build.prop via
#    PRODUCT_PROPERTY_OVERRIDES triggers vendor_init SELinux denials (last_kmsg
#    verified: tcontext=build_prop / userdebug_or_eng_prop), so do not duplicate
#    them here.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 5b. Signing
#
#     A release build must be signed with our own keys, not AOSP's public
#     test-keys. Two reasons, and the second is the one people forget:
#
#       1. ro.build.tags=test-keys is a bright red flag to apps that check.
#       2. test-keys are PUBLIC. Anyone can sign an APK with them and a device
#          built on test-keys will accept it as a system-signature match. That is
#          not a cosmetic problem; it is a privilege-escalation vector shipped in
#          the zip.
#
#     The keys are generated by build/gen-release-keys.sh and are deliberately NOT
#     in git (see .gitignore). So this is conditional: if the keys are absent, the
#     build still works and falls back to whatever the tree defaults to, rather
#     than failing with a confusing "certificate not found" deep in Soong.
#
#     Consequence, stated plainly: a build made without the keys is NOT a release
#     build. `build/verify-release.sh` checks that before anything is published.
# ---------------------------------------------------------------------------
XT_KEY_DIR := vendor/xt/keys

ifneq (,$(wildcard $(XT_KEY_DIR)/releasekey.pk8))
    PRODUCT_DEFAULT_DEV_CERTIFICATE := $(XT_KEY_DIR)/releasekey
    PRODUCT_EXTRA_RECOVERY_KEYS += $(XT_KEY_DIR)/releasekey
else
    # Leave the default alone. Do not set test-keys here either — that would bake
    # the mistake in. verify-release.sh fails the publish instead.
    $(warning XT: $(XT_KEY_DIR)/releasekey.pk8 not found — this is an UNSIGNED/test-key build, not a release.)
endif

# ---------------------------------------------------------------------------
# 6. Theme overlays (RROs) — these DO exist in this repo today, so they are
#    listed unconditionally. All four build; XtThemeNothing is enabled by
#    default via overlay/config/config.xml.
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    XtThemeNothing \
    XtThemeNothingLight \
    XtThemeMonet \
    XtThemeStock

# ---------------------------------------------------------------------------
# 7. GApps trim
# ---------------------------------------------------------------------------
include vendor/xt/config/xt-gapps.mk

# ---------------------------------------------------------------------------
# 8. First-party apps
#
#    All XT-OS system utilities (ANR Guard, VoLTE/LTE Lab, Kernel/RAM/PSI
#    Status Monitor, RRO Theme Switcher, and First-Boot Provisioner) are merged
#    into a single unified privileged app: XtDebug (os.xt.debug).
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    XtDebug

PRODUCT_COPY_FILES += \
    vendor/xt/apps/XtDebug/privapp-permissions-xt-debug.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-xt-debug.xml

# ---------------------------------------------------------------------------
# 9. OPTIONAL layers
#
#    Fonts and artwork are still absent. Referencing them directly would fail the
#    build, so they stay isolated in a fragment generated by build/gen-assets.sh:
#
#        vendor/xt/config/xt-assets.mk
#
#    `-include` (not `include`) means a missing fragment is silently skipped,
#    which keeps `m bacon` green while the design assets are still being
#    acquired. Run build/gen-assets.sh after adding fonts/artwork to regenerate.
# ---------------------------------------------------------------------------
-include vendor/xt/config/xt-assets.mk
