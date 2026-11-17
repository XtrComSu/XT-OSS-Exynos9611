#
# XT-OS GApps trim
#
# Infinity X ships WITH_GAPPS := true with a fairly complete package set. On a
# 6 GB / 4-core A73 device every extra Google package costs resident memory,
# super-partition space, and idle wakeups. Measured rationale in docs/INTEGRITY.md.
#
# KEEP  — load-bearing for Play Integrity / Play Store / account plumbing.
# DROP  — everything the user can install from the Play Store themselves.
#
# Applied after the Infinity X product config has populated PRODUCT_PACKAGES, so
# this must be included last from xt-common.mk.
#

# Packages we explicitly remove. Listed by module name as defined in
# vendor/pixel/gms and vendor/infinity. If a name is not present, filter-out is
# a no-op, which makes this list safe to over-specify.
XT_GAPPS_DROP := \
    GoogleVelvet \
    Velvet \
    GoogleMaps \
    GoogleGmail \
    GoogleYouTube \
    GooglePhotos \
    GoogleDrive \
    GoogleCalendar \
    GoogleKeep \
    GoogleFilesGo \
    GoogleChrome \
    GoogleRestore \
    GoogleOne \
    GoogleMarkup \
    PixelLauncher \
    PixelTips \
    DevicePersonalizationServices \
    Turbo \
    TurboPrebuilt \
    WellbeingPrebuilt \
    SoundPickerPrebuilt \
    WallpaperPickerGoogleRelease \
    PixelThemesStub \
    GoogleCalendarSyncAdapter

PRODUCT_PACKAGES := $(filter-out $(XT_GAPPS_DROP),$(PRODUCT_PACKAGES))

# CarrierServices is required for RCS on most carriers. It is deliberately NOT
# in the drop list. Verify RCS at the Phase 4 gate before considering removal.
#
# GoogleContactsSyncAdapter is intentionally kept: it is tiny and users expect
# contact sync to work out of the box.
