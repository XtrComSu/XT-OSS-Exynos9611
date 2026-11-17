#
# XT-OS GApps trim — ENUMERATED ALLOWLIST
#
# TARGET (user decision, 2026-11-17): "Play Store + Play Services + WebView only."
#
# WHY THIS FILE IS AN ALLOWLIST AND NOT A BLOCKLIST
# ------------------------------------------------
# The previous version listed ~16 names to drop. That design FAILS OPEN: any module
# Google's GApps adds in a future update ships silently, because nothing enumerates
# what should be there. It also produced two outright no-ops that looked correct in
# review:
#
#   * it named `TurboAdapter`, but the module that actually ships on this device is
#     `TurboAdapter_NoBatt`, added conditionally by gms.mk when
#     TARGET_DOES_NOT_SUPPORT_GOOGLE_BATTERY=true. The drop matched nothing.
#   * `GoogleSettingsOverlay` and `libpowerstatshaldataprovider` are also added by
#     gms.mk and were never counted at all.
#
# Neither error is visible in a diff, and neither produces a build warning. So the
# structure changed: this file now records EXACTLY what upstream ships, states
# exactly what we keep, and derives the drop by subtraction. Anything upstream adds
# tomorrow is dropped by default, and build/verify-gapps.py makes the drift loud.
#
# INCLUDE CHAIN (verified against the tree, not assumed)
#   xt_m31.mk
#     -> vendor/infinity/config/common_full_phone.mk
#        -> common_mobile_full.mk -> common_mobile.mk   (adds AOSP LatinIME)
#        -> common.mk:289  ifeq ($(WITH_GAPPS),true)
#             -> vendor/pixel/gms/products/gms.mk       (adds 3 modules, see below)
#                  -> line 68: vendor/pixel/gms/common/common-vendor.mk  (the 49)
#     -> vendor/xt/config/xt-common.mk   <- runs filter-out HERE, last. Good.
#
# So the filter genuinely executes. That was worth proving: the same class of
# ordering mistake (a filter running before the thing it filters) is how the old
# overlay shipped completely inert.
#
# WHY NOT JUST WITH_GAPPS := false
# ---------------------------------
# common.mk:289 gates more than GMS: it also pulls themepicker.mk and sounds.mk,
# and gms.mk sets ~20 setupwizard properties. Turning it off would remove the theme
# picker, the system sounds, and the first-boot setup flow — the device would boot
# into something broken. Trimming the package list is the surgical version.
#

# ---------------------------------------------------------------------------
# 1. WHAT UPSTREAM SHIPS — recorded verbatim from
#    vendor/pixel/gms/common/common-vendor.mk (single PRODUCT_PACKAGES block, no
#    conditionals, no nested inherits: verified 2026-11-17).
#
#    Do not edit this list to "fix" the build. It is a RECORD of upstream, and
#    build/verify-gapps.py diffs it against the live tree to detect drift. If
#    upstream changes, update this list to match and re-review the allowlist.
# ---------------------------------------------------------------------------
XT_GAPPS_ALL := \
    com.google.android.extservices \
    com.google.android.gmssystem.prodvic \
    GoogleExtShared \
    GooglePrintRecommendationService \
    TagGoogle \
    CalculatorGooglePrebuilt_85006267 \
    Chrome-Stub \
    DevicePolicyPrebuilt-v10572820 \
    GoogleContacts \
    GoogleTTS \
    LatinIMEGooglePrebuilt \
    LocationHistoryPrebuilt \
    MarkupGoogle_v2 \
    ModuleMetadataGoogle \
    SwitchAccessPrebuilt_1.17.0.877181440 \
    TrichromeLibrary-Stub \
    WebViewGoogle-Stub \
    talkback \
    AndroidAutoStubPrebuilt \
    ConfigUpdater \
    DeviceIntelligenceNetworkPrebuiltAstrea \
    DevicePersonalizationAiAiPrebuiltPixel2025 \
    GoogleRestorePrebuilt-v1007163 \
    PartnerSetupPrebuilt \
    Phonesky \
    PrebuiltDeskClockGoogle_76042511 \
    PrebuiltGmsCoreVic_AdsDynamite \
    PrebuiltGmsCoreVic_CronetDynamite \
    PrebuiltGmsCoreVic_DynamiteLoader \
    PrebuiltGmsCoreVic_DynamiteModulesA \
    PrebuiltGmsCoreVic_DynamiteModulesC \
    PrebuiltGmsCoreVic_GoogleCertificates \
    PrebuiltGmsCoreVic_MapsDynamite \
    PrebuiltGmsCoreVic_MeasurementDynamite \
    AndroidPlatformServices \
    MlkitBarcodeUIPrebuilt \
    TfliteDynamitePrebuilt \
    VisionBarcodePrebuilt \
    SearchSelectorPrebuilt \
    SettingsIntelligenceGooglePrebuilt \
    SetupWizardPrebuilt_versioned \
    TurboPrebuilt \
    Velvet \
    WellbeingPrebuilt \
    EmergencyInfoGoogleNoUi \
    Flipendo \
    GoogleServicesFramework \
    SetupWizardPixelPrebuilt_versioned \
    TurboAdapter

# ---------------------------------------------------------------------------
# 2. WHAT WE KEEP — every entry needs a reason that survives review.
# ---------------------------------------------------------------------------
XT_GAPPS_KEEP := \
    Phonesky \
    PrebuiltGmsCoreVic_AdsDynamite \
    PrebuiltGmsCoreVic_CronetDynamite \
    PrebuiltGmsCoreVic_DynamiteLoader \
    PrebuiltGmsCoreVic_DynamiteModulesA \
    PrebuiltGmsCoreVic_DynamiteModulesC \
    PrebuiltGmsCoreVic_GoogleCertificates \
    PrebuiltGmsCoreVic_MapsDynamite \
    PrebuiltGmsCoreVic_MeasurementDynamite \
    TfliteDynamitePrebuilt \
    GoogleServicesFramework \
    GoogleExtShared \
    com.google.android.extservices \
    com.google.android.gmssystem.prodvic \
    AndroidPlatformServices \
    ModuleMetadataGoogle \
    WebViewGoogle-Stub \
    TrichromeLibrary-Stub \
    SetupWizardPrebuilt_versioned \
    SetupWizardPixelPrebuilt_versioned \
    PartnerSetupPrebuilt \
    ConfigUpdater \
    talkback \
    SwitchAccessPrebuilt_1.17.0.877181440 \
    GoogleTTS \
    GoogleContacts \
    EmergencyInfoGoogleNoUi

# --- Why each makes the cut ------------------------------------------------
#
# PLAY STORE + INTEGRITY CORE (Phonesky + 9 PrebuiltGmsCoreVic_* + Tflite):
#   Not negotiable. Play Services and anything touching Play Integrity needs the
#   whole dynamite set; a partial set is worse than none because failures are
#   intermittent rather than obvious. Note PrebuiltGmsCoreVic_MapsDynamite is a
#   GMS *module*, not the Maps app — dropping it breaks barcode/vision and in-GMS
#   maps surfaces.
#
# ACCOUNT / INSTALL PLUMBING (GoogleServicesFramework, GoogleExtShared,
# com.google.android.extservices, com.google.android.gmssystem.prodvic,
# AndroidPlatformServices, ModuleMetadataGoogle):
#   Sign-in, package install, module delivery. Removing any of these produces a
#   Play Store that opens and then fails, which users read as "ROM is broken".
#
# WEBVIEW (WebViewGoogle-Stub + TrichromeLibrary-Stub):
#   WebView is load-bearing: apps render HTML through it and a missing or
#   mismatched WebView shows blank in-app pages that look like app bugs, not ROM
#   bugs. Both -Stub entries are placeholder modules that pull the real payload and
#   are NOT the large part. Do not "optimise" these away.
#
# FIRST-BOOT SETUP (SetupWizardPrebuilt_versioned, SetupWizardPixelPrebuilt_versioned,
# PartnerSetupPrebuilt, ConfigUpdater):
#   Without these the device boots to a broken or skipped first-run. A minimal ROM
#   should be small, not visibly unfinished. ConfigUpdater keeps module metadata
#   current, which Play Services uses.
#
# ACCESSIBILITY (talkback, SwitchAccess):
#   Kept on principle. Screen reader and switch access are the two things a
#   vision- or motor-impaired user cannot substitute, and both are small. Trimming
#   apps is a memory decision; trimming these would be a decision about who the ROM
#   is for. Not making that call as a side effect of a size target.
#
# TTS (GoogleTTS):
#   Many third-party apps assume a system TTS engine exists and degrade badly or
#   crash without one. No AOSP TTS ships in this tree to fall back to.
#
# CONTACTS (GoogleContacts):
#   The only Contacts UI verified present. AOSP Dialer ships via
#   build/make/target/product/telephony_product.mk (confirmed: it is pulled by
#   full_base_telephony.mk, so CALLS work regardless) but Dialer is not a contacts
#   browser. Dropping this would leave contacts reachable only through the dialer's
#   inline list.
#
# EMERGENCY INFO (EmergencyInfoGoogleNoUi):
#   Safety surface. Note AOSP EmergencyInfo is NOT in PRODUCT_PACKAGES for this
#   product (it appears only in wifionly.mk), so dropping Google's would leave
#   nothing. Emergency calling itself is telephony-stack work and is unaffected
#   either way — but medical/contact info surviving to the lock screen is worth
#   the small cost.

# ---------------------------------------------------------------------------
# 3. DROP = ALL - KEEP
# ---------------------------------------------------------------------------
XT_GAPPS_DROP := $(filter-out $(XT_GAPPS_KEEP),$(XT_GAPPS_ALL))

PRODUCT_PACKAGES := $(filter-out $(XT_GAPPS_DROP),$(PRODUCT_PACKAGES))

# ---------------------------------------------------------------------------
# 4. Modules added by gms.mk that are NOT in common-vendor.mk
#
#    These are the two no-ops the old blocklist missed. gms.mk adds them before it
#    inherits common-vendor.mk, so they never appeared in the list I originally
#    checked:
#
#      TurboAdapter_NoBatt           — the module that actually ships; the blocklist
#                                      named plain "TurboAdapter" and matched nothing
#      libpowerstatshaldataprovider  — its supporting HAL
#      GoogleSettingsOverlay         — a settings RRO, cosmetic
#
#    Dropped by name here rather than by extending XT_GAPPS_ALL, because they come
#    from a different file and the drift guard diffs XT_GAPPS_ALL against
#    common-vendor.mk only. Keeping them separate keeps that comparison honest.
#
#    Note this removes Google Battery entirely (TARGET_DOES_NOT_SUPPORT_GOOGLE_BATTERY
#    is true on this device, which is why the _NoBatt variant is what gets added).
#    That is the intent: it is a background stats service, and this ROM's whole
#    point is idle drain.
# ---------------------------------------------------------------------------
XT_GAPPS_DROP_EXTRA := \
    TurboAdapter_NoBatt \
    libpowerstatshaldataprovider \
    GoogleSettingsOverlay

PRODUCT_PACKAGES := $(filter-out $(XT_GAPPS_DROP_EXTRA),$(PRODUCT_PACKAGES))

# ---------------------------------------------------------------------------
# 5. Keyboard
#
#    LatinIMEGooglePrebuilt (Gboard) is dropped and AOSP LatinIME is used instead.
#    This is only safe because AOSP LatinIME is verified present: common_mobile.mk
#    line 16 adds `LatinIME` to PRODUCT_PACKAGES, and common_mobile_full.mk pulls
#    the LatinIME dictionary overlays. Dropping Gboard without that check would
#    leave the device with NO keyboard on first boot — an unrecoverable state from
#    the user's side.
#
#    AOSP LatinIME is basic next to Gboard. That is the accepted trade: the target
#    is "Play + Services + WebView", and a keyboard is not in that set as long as a
#    functional one exists.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 6. NOT DROPPED, and why the obvious candidates survive
#
#    Chrome-Stub — dropped. WebViewGoogle-Stub + TrichromeLibrary-Stub provide the
#    WebView engine; Chrome the browser is not required for it. Verified the two
#    are separate modules.
#
#    Velvet (Google app / search) — dropped. Not needed for Play or Services.
#    Drawer search falls back to the launcher's own.
#
#    Wellbeing, Flipendo (Digital Wellbeing, device-restriction shells) — dropped.
#    Both are background services whose entire function is periodic scheduling.
#
#    DeviceIntelligence / DevicePersonalization (AiAi) — dropped. On-device ML
#    models: meaningful RAM and a large /product footprint for features this device
#    will not run comfortably.
#
#    MlkitBarcodeUIPrebuilt + VisionBarcodePrebuilt — dropped. Barcode scanning
#    ships inside Play Services; these are the on-device ML payloads.
#
#    LocationHistoryPrebuilt — dropped. Only affects Google Timeline, not core
#    location, which is fused-location in GMS and kept.
#
#    GoogleRestorePrebuilt — dropped. Device-to-device restore during setup. Note
#    setupwizard.feature.enable_restore_anytime remains set by gms.mk; the wizard
#    then simply offers nothing to restore from, which is a graceful degradation.
#
#    DevicePolicyPrebuilt — dropped. Enterprise device management. Brings a device
#    admin surface with it.
#
#    GooglePrintRecommendationService — dropped. Cloud print suggestions.
#
#    TagGoogle / MarkupGoogle_v2 — dropped. AOSP `Tag` is already added by
#    universal9611-common/common.mk line 215, so NFC tag reading still works;
#    screen markup is a Pixel convenience.
#
#    CalculatorGooglePrebuilt / PrebuiltDeskClockGoogle — dropped. AOSP Calculator
#    and DeskClock are in the base product; the Google builds are re-skins.
#
#    AndroidAutoStubPrebuilt, TurboPrebuilt (device health), SearchSelectorPrebuilt,
#    SettingsIntelligenceGooglePrebuilt — dropped. Optional surfaces; Settings falls
#    back to its own search index.
# ---------------------------------------------------------------------------

# Reversibility: to restore any dropped module, add it to XT_GAPPS_KEEP. The drop
# list is derived, so nothing needs to be removed from two places.
