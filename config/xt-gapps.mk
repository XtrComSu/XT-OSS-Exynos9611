#
# XT-OS GApps trim — EXPLICIT INCLUDE LIST
#
# TARGET (user decision, 2026-11-17): "Play Store + Play Services + WebView only."
#
# =============================================================================
# READ THIS FIRST: the previous version of this file did not work at all.
# =============================================================================
#
# It was a filter-out against PRODUCT_PACKAGES:
#
#     XT_GAPPS_DROP := $(filter-out $(XT_GAPPS_KEEP),$(XT_GAPPS_ALL))
#     PRODUCT_PACKAGES := $(filter-out $(XT_GAPPS_DROP),$(PRODUCT_PACKAGES))
#
# That looks correct, and a reviewer would reasonably believe it. It is a no-op,
# because of how AOSP evaluates product makefiles:
#
#   $(call inherit-product, X) does NOT include X at that point. It appends a
#   literal marker word to each product variable:
#
#       PRODUCT_PACKAGES := $(PRODUCT_PACKAGES) @inherit:vendor/pixel/gms/products/gms.mk
#
#   Those markers are expanded much later by import-nodes. So when a product
#   makefile runs, PRODUCT_PACKAGES holds only what has been added DIRECTLY so
#   far — not the thousands of modules inherited from upstream.
#
#   Measured on the real tree by instrumenting this file (2026-11-17):
#
#       XTPROBE drop_count=22          <- our drop list is correct
#       XTPROBE velvet_in_drop=1       <- Velvet is in it
#       XTPROBE pp_word_count=4        <- PRODUCT_PACKAGES had FOUR words here
#       XTPROBE inherit_markers=0      <- and not even markers at this point
#
#   Four words. filter-out of a 22-name list against 4 names removes nothing.
#   Verified end-to-end: `get_build_var PRODUCT_PACKAGES` still contained
#   Velvet=1, LatinIMEGooglePrebuilt=1, TurboAdapter_NoBatt=1 afterwards.
#
#   AOSP has no supported post-inherit removal hook. So a subtraction is not
#   expressible here, and the only working approach is to never add the modules:
#   do not inherit the GMS bundle, and list exactly what we want.
#
# WHY NOT WITH_GAPPS := false
# ---------------------------
# common.mk:289 gates three inherits with that flag:
#
#     $(call inherit-product, vendor/pixel/gms/products/gms.mk)
#     $(call inherit-product, vendor/pixel/themepicker/products/themepicker.mk)
#     $(call inherit-product, vendor/pixel/sounds/products/sounds.mk)
#
# Setting it false would drop the theme picker and the Pixel sound set along with
# GMS. Instead this file inherits the two we DO want and never inherits gms.mk.
#
# Note the knock-on: version.mk:32 uses WITH_GAPPS only to name the zip (GAPPS vs
# VANILLA), and BoardConfigReservedSize.mk:8 uses it to size the product partition.
# Neither affects what gets installed, so WITH_GAPPS stays true and the product
# keeps its 'GAPPS' identity and partition sizing. The flag no longer decides
# package selection — this file does.
#
# WHAT WE LOSE BY NOT INHERITING gms.mk
# -------------------------------------
# gms.mk (69 lines) contributed exactly three module groups plus ~24 properties.
# Each was reviewed rather than dropped blind:
#
#   MODULES (now listed explicitly below)
#     TurboAdapter_NoBatt          battery stats adapter, gated on
#                                  TARGET_DOES_NOT_SUPPORT_GOOGLE_BATTERY=true
#     libpowerstatshaldataprovider the matching .so in system_ext/lib64
#     GoogleSettingsOverlay        RRO; replaced by our own theme overlays
#                                  (deliberately NOT carried over — see below)
#
#   PROPERTIES (all carried over verbatim in section 3)
#     ro.opa.eligible_device=true                  Assistant eligibility
#     ~23 setupwizard.feature.* keys               first-boot flow
#     setupwizard.theme=glif_expressive            setup wizard visual style
#     enable_one_pane_in_embedded_activity         tablet-only, harmless here
#
# Dropping the setupwizard properties would have given a visibly broken first-boot
# experience, which is why they are reproduced rather than skipped.
#
# GoogleSettingsOverlay is NOT carried over on purpose: it replaces Settings
# strings/icons, and this ROM ships its own Settings surface treatment. Carrying
# both causes resource-substitution conflicts with no benefit.
#
# REVERSIBILITY
# -------------
# To restore a Google module: add it to XT_GAPPS_KEEP below. To go back to stock
# Infinity X GApps: set XT_GAPPS_OVERRIDE_UPSTREAM := true, which re-inherits
# gms.mk unchanged. That path is kept deliberately so this decision is testable
# against upstream rather than a one-way door.
#
# build/verify-gapps.py enforces the invariant: XT_GAPPS_KEEP must contain no
# names absent from XT_GAPPS_ALL. It cannot detect the ordering bug above — a
# static check cannot see make-time variable state — so the real guard is
# build/verify-product.sh, which inspects the staged product tree for Velvet and
# friends. That check would have caught this.
#

# ---------------------------------------------------------------------------
# 1. WHAT UPSTREAM SHIPS — recorded verbatim from
#    vendor/pixel/gms/common/common-vendor.mk (single PRODUCT_PACKAGES block,
#    no conditionals, no nested inherits: verified 2026-11-17).
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
    ConfigUpdater \
    DevicePolicyPrebuilt-v10572820 \
    EmergencyInfoGoogleNoUi \
    GoogleContacts \
    GoogleTTS \
    LatinIMEGooglePrebuilt \
    LocationHistoryPrebuilt \
    MarkupGoogle_v2 \
    AndroidAutoStubPrebuilt \
    DeviceIntelligenceNetworkPrebuiltAstrea \
    DevicePersonalizationAiAiPrebuiltPixel2025 \
    GoogleRestorePrebuilt-v1007163 \
    PrebuiltDeskClockGoogle_76042511 \
    MlkitBarcodeUIPrebuilt \
    VisionBarcodePrebuilt \
    PartnerSetupPrebuilt \
    Phonesky \
    PrebuiltGmsCoreVic_AdsDynamite \
    PrebuiltGmsCoreVic_CronetDynamite \
    PrebuiltGmsCoreVic_DynamiteLoader \
    PrebuiltGmsCoreVic_DynamiteModulesA \
    PrebuiltGmsCoreVic_DynamiteModulesC \
    PrebuiltGmsCoreVic_GoogleCertificates \
    PrebuiltGmsCoreVic_MapsDynamite \
    PrebuiltGmsCoreVic_MeasurementDynamite \
    SearchSelectorPrebuilt \
    SettingsIntelligenceGooglePrebuilt \
    SetupWizardPrebuilt_versioned \
    SetupWizardPixelPrebuilt_versioned \
    TrichromeLibrary-Stub \
    TurboAdapter \
    TurboPrebuilt \
    Velvet \
    WebViewGoogle-Stub \
    WellbeingPrebuilt \
    Flipendo \
    ModuleMetadataGoogle \
    GoogleServicesFramework \
    AndroidPlatformServices \
    TfliteDynamitePrebuilt \
    talkback \
    SwitchAccessPrebuilt_1.17.0.877181440 \

# ---------------------------------------------------------------------------
# 2. WHAT WE KEEP — this list is now AUTHORITATIVE, not a subtraction input.
#
#    Every name here must be a real Soong module or the build fails with
#    "module not found". All 30 were verified present in the generated install
#    graph on 2026-11-17, including the three non-APK ones:
#      com.google.android.extservices   xml/overlay module, not an APK
#      com.google.android.gmssystem.prodvic  xml/overlay module, not an APK
#      libpowerstatshaldataprovider     .so, installs to system_ext/lib64
#
#    Grouped by why each is required.
# ---------------------------------------------------------------------------
#    NOT INCLUDED, deliberately: WebViewGoogle-Stub and TrichromeLibrary-Stub.
#    Both declare `overrides: ["webview"]` / ["TrichromeLibrary"], and a soong
#    override REMOVES the overridden module from the install set. Keeping them
#    meant the real AOSP WebView provider (external/chromium-webview, 262 MB,
#    arm64 prebuilt) was knocked out and the ROM shipped with only a 12 KB stub
#    as its WebView -- so no browser or in-app web view could render anything.
#    The stubs exist so Play Store can swap in a newer WebView later; dropping
#    them gives a working provider out of the box, which matters more.
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
    ConfigUpdater \
    talkback \
    SwitchAccessPrebuilt_1.17.0.877181440 \
    GoogleTTS \
    GoogleContacts \
    EmergencyInfoGoogleNoUi

# Non-APK pieces gms.mk added alongside the bundle. Kept because they are
# infrastructure, not user-facing apps: battery stats reporting and the overlay
# that Settings themeing expects.
XT_GAPPS_EXTRA_PACKAGES := \
    TurboAdapter_NoBatt \
    libpowerstatshaldataprovider

# ---------------------------------------------------------------------------
# 3. THE GMS BUNDLE — inherit only when explicitly overriding.
#
#    Default: NOT inherited. Section 4 adds the allowlist instead.
# ---------------------------------------------------------------------------
XT_BUILD_VANILLA ?= true
XT_GAPPS_OVERRIDE_UPSTREAM ?= false

ifeq ($(XT_BUILD_VANILLA),true)
  # ---------------------------------------------------------------------------
  # PURE VANILLA BUILD (NO GAPPS)
  # ---------------------------------------------------------------------------
  # Completely omit Google Play Services, Play Store, and proprietary GMS blobs.
  # System utilities, theme overlays, and custom apps remain active.
else
ifeq ($(XT_GAPPS_OVERRIDE_UPSTREAM),true)
  # Escape hatch: stock Infinity X GApps, for A/B testing against our trim.
  $(call inherit-product, vendor/pixel/gms/products/gms.mk)
else
  # HARD REQUIREMENT: WITH_GAPPS must be false, or common.mk:289 inherits gms.mk
  # anyway and the allowlist below is added ON TOP of all 49 modules — which is
  # precisely the failure this file exists to prevent. A static review would not
  # catch that, so it is an error rather than a comment.
  #
  # This is checked here because here is the only place that knows the allowlist
  # is meant to be exclusive.
  ifeq ($(WITH_GAPPS),true)
    $(error XT: WITH_GAPPS=true re-inherits vendor/pixel/gms/products/gms.mk via \
      vendor/infinity/config/common.mk:289, which adds all 49 GApps modules on top \
      of XT_GAPPS_KEEP. Set WITH_GAPPS := false in the product makefile (the picker \
      and sounds bundles are inherited explicitly below, so nothing else is lost).)
  endif
  # THE NAMESPACE — without this, every module above silently fails to install.
  PRODUCT_SOONG_NAMESPACES += vendor/pixel/gms/common

  PRODUCT_PACKAGES += $(XT_GAPPS_KEEP) $(XT_GAPPS_EXTRA_PACKAGES)
endif

# ---------------------------------------------------------------------------
# 4. PROPERTIES gms.mk used to set. Reproduced verbatim.
#
#    These are not cosmetic. setupwizard.feature.* switches drive the first-boot
#    flow; without them SetupWizard opens in a reduced/legacy mode. Provenance:
#    vendor/pixel/gms/products/gms.mk lines 27-66.
# ---------------------------------------------------------------------------
PRODUCT_PRODUCT_PROPERTIES += \
    ro.opa.eligible_device=true

PRODUCT_PRODUCT_PROPERTIES += \
    ro.setupwizard.enterprise_mode=1 \
    ro.setupwizard.esim_cid_ignore=00000001 \
    setupwizard.feature.baseline_setupwizard_enabled=true \
    setupwizard.feature.day_night_mode_enabled=true \
    setupwizard.feature.default_locale_enhancement_enabled=true \
    setupwizard.feature.device_info_icon_enabled=true \
    setupwizard.feature.enable_gil= \
    setupwizard.feature.enable_gil_logging=true \
    setupwizard.feature.enable_minors_setup_flow=true \
    setupwizard.feature.enable_parental_notice_activity=true \
    setupwizard.feature.enable_parental_setup=true \
    setupwizard.feature.enhanced_setup_design_metrics=true \
    setupwizard.feature.is_suw_onboarding_contract_enabled=true \
    setupwizard.feature.joined_up_loading=true \
    setupwizard.feature.locale_agnostic_enabled=true \
    setupwizard.feature.enable_quick_start_flow=true \
    setupwizard.feature.enable_restore_anytime=true \
    setupwizard.feature.enable_wifi_tracker=true \
    setupwizard.feature.lifecycle_refactoring=true \
    setupwizard.feature.notification_refactoring=true \
    setupwizard.feature.portal_notification=true \
    setupwizard.feature.provisioning_profile_mode=true

PRODUCT_PRODUCT_PROPERTIES += \
    setupwizard.theme=glif_expressive

ifeq ($(TARGET_IS_TABLET),true)
PRODUCT_PRODUCT_PROPERTIES += \
    enable_one_pane_in_embedded_activity=true
endif
endif

# ---------------------------------------------------------------------------
# 5. The other two bundles common.mk:289 gated. Inherited explicitly so that
#    keeping them no longer depends on the GApps flag at all.
# ---------------------------------------------------------------------------
$(call inherit-product, vendor/pixel/themepicker/products/themepicker.mk)
$(call inherit-product, vendor/pixel/sounds/products/sounds.mk)
