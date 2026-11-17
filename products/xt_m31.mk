#
# XT-OS product for Samsung Galaxy m31 (SM-M315F)
# Derived from Parbindar7/android_device_samsung_m31@lineage-24.0
#
# Two deltas vs the upstream lineage_m31.mk:
#   1. vendor/lineage -> vendor/infinity (Infinity X has no vendor/lineage)
#   2. PRODUCT_NAME lineage_m31 -> xt_m31, plus XT build flags
#

# NFC / device-specific toggles
TARGET_USES_SLSI_NFC := true

# Inherit device configuration
$(call inherit-product, device/samsung/m31/device.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Infinity X common phone config (NOT vendor/lineage)
$(call inherit-product, vendor/infinity/config/common_full_phone.mk)

# XT overlay layer
$(call inherit-product, vendor/xt/config/xt-common.mk)

# Shipping API level
PRODUCT_SHIPPING_API_LEVEL := 29

# Client-id base
PRODUCT_GMS_CLIENTID_BASE := android-samsung-ss

# Build fingerprint — stock, for Play Integrity coherence
PRODUCT_BUILD_PROP_OVERRIDES += \
	BuildDesc="m31nsxx-user 12 SP1A.210812.016 M315FXXU3CWA2 release-keys" \
	BuildFingerprint="samsung/m31nsxx/m31:12/SP1A.210812.016/M315FXXU3CWA2:user/release-keys"

## Device configuration
PRODUCT_NAME := xt_m31
PRODUCT_DEVICE := m31
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-M315F
PRODUCT_MANUFACTURER := samsung

TARGET_BOOT_ANIMATION_RES := 1080

## XT flags
INFINITY_MAINTAINER := XtrComSu
# WITH_GAPPS stays FALSE even though this ROM ships GApps.
#
# That flag does not mean "include GApps" here — common.mk:289 uses it to inherit
# the whole vendor/pixel/gms bundle, all 49 modules. We want a 30-module subset,
# and AOSP offers no way to remove a module after inherit-product has queued it
# (inherit-product only appends @inherit: markers; the real PRODUCT_PACKAGES is
# assembled later by import-nodes). So the only workable route is: do not inherit
# the bundle, and list what we want.
#
# config/xt-gapps.mk owns that list and inherits themepicker + sounds explicitly,
# which is what this flag used to also pull in. It errors at parse time if this is
# ever set back to true, so the two cannot drift apart silently.
WITH_GAPPS := false
WITHOUT_RESERVED_SIZE := true
