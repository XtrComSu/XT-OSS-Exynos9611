#
# XT-OS GApps trim
#
# VERIFIED against the actual upstream package list, not guessed.
#
# Source: gitlab.com/tejas101k/proprietary_vendor_pixel_gms @ branch `seventeen`
#         (the repo Infinity X's manifest pulls into vendor/pixel/gms),
#         file common/common-vendor.mk — read 2026-11-17.
#
# Every name below was copied from that file's PRODUCT_PACKAGES blocks. The
# earlier draft of this file listed names like GoogleMaps/GoogleGmail/GooglePhotos
# that DO NOT EXIST in this GApps build — which would have been silent no-ops and
# an ineffective trim. Corrected here.
#
# Rationale: on a 6 GB / 4-core A73 device each retained Google package costs
# resident memory, /product space, and idle wakeups. See docs/INTEGRITY.md §3.
#

# ---------------------------------------------------------------------------
# DROP — heavy, non-load-bearing, or already replaced by our own apps
# ---------------------------------------------------------------------------
XT_GAPPS_DROP := \
    Velvet \
    WellbeingPrebuilt \
    TurboPrebuilt \
    TurboAdapter \
    AndroidAutoStubPrebuilt \
    DevicePersonalizationAiAiPrebuiltPixel2025 \
    DeviceIntelligenceNetworkPrebuiltAstrea \
    LocationHistoryPrebuilt \
    MarkupGoogle_v2 \
    GooglePrintRecommendationService \
    GoogleRestorePrebuilt-v1007163 \
    DevicePolicyPrebuilt-v10572820 \
    Flipendo \
    CalculatorGooglePrebuilt_85006267 \
    PrebuiltDeskClockGoogle_76042511 \
    Chrome-Stub

PRODUCT_PACKAGES := $(filter-out $(XT_GAPPS_DROP),$(PRODUCT_PACKAGES))

# ---------------------------------------------------------------------------
# Notes on what is deliberately KEPT, and why
# ---------------------------------------------------------------------------
#
# Play Services core + dynamite modules (all PrebuiltGmsCoreVic_*):
#   Non-negotiable. Phonesky and every Play-Integrity-dependent app need them.
#   PrebuiltGmsCoreVic_MapsDynamite is a *module of GMS*, not the Maps app —
#   dropping it breaks Maps-in-Play-Services and barcode/vision paths.
#
# GoogleServicesFramework, Phonesky, AndroidPlatformServices, GoogleExtShared,
# com.google.android.extservices, com.google.android.gmssystem.prodvic,
# ModuleMetadataGoogle:
#   Account/auth/install plumbing. Keep.
#
# PartnerSetupPrebuilt, SetupWizardPrebuilt_versioned,
# SetupWizardPixelPrebuilt_versioned, ConfigUpdater:
#   First-boot account flow. Keep — without them the device boots to a broken
#   setup experience, which reads as "buggy ROM" rather than "minimal".
#
# WebViewGoogle-Stub + TrichromeLibrary-Stub:
#   KEEP. WebView is not optional: many apps render HTML through it, and a
#   missing/mismatched WebView produces blank in-app pages that look like app
#   bugs. The -Stub entries are placeholders that pull the real payload; they are
#   small. Do not "optimise" these away.
#
# LatinIMEGooglePrebuilt (Gboard):
#   KEEP for v1.0. We ship no keyboard of our own. Dropping this without adding
#   an AOSP keyboard leaves the device with no IME on first boot.
#
# GoogleTTS:
#   KEEP. Many third-party apps assume a system TTS engine exists.
#
# talkback, SwitchAccessPrebuilt_1.17.0.877181440:
#   KEEP. Accessibility. Removing these is a user-hostile "optimisation" and the
#   memory cost is small.
#
# GoogleContacts, TagGoogle, SearchSelectorPrebuilt, GoogleExtShared:
#   Small, and their absence is noticed immediately (contact sync, NFC tags,
#   setup-wizard search).
#
# ---------------------------------------------------------------------------
# Baseline correction for v1.0
# ---------------------------------------------------------------------------
# These were KEPT above but are candidates for a second pass once we have real
# measurements on hardware:
#   - LatinIMEGooglePrebuilt, IF a suitable AOSP keyboard is added to the build
#   - GoogleTTS, IF nothing in the shipping app set needs it
#   - LocationHistoryPrebuilt was dropped; reconsider if a user reports
#     Timeline/Location History breakage (it is not needed for basic location)
#
# Every drop in this file is reversible by removing one name — that is the point
# of keeping the list explicit rather than using a pattern match.
