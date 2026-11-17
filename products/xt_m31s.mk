#
# XT-OS product for Samsung Galaxy m31s (SM-M317F)
# Derived from Parbindar7/android_device_samsung_m31s@lineage-24.0
#
# Two deltas vs the upstream lineage_m31s.mk:
#   1. vendor/lineage -> vendor/infinity (Infinity X has no vendor/lineage)
#   2. PRODUCT_NAME lineage_m31s -> xt_m31s, plus XT build flags
#

# NFC / device-specific toggles
TARGET_USES_SLSI_NFC := true

# Inherit device configuration
$(call inherit-product, device/samsung/m31s/device.mk)
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
	BuildDesc="m31snsxx-user 12 SP1A.210812.016 M317FXXU3DWB3 release-keys" \
	BuildFingerprint="samsung/m31snsxx/m31s:12/SP1A.210812.016/M317FXXU3DWB3:user/release-keys"

## Device configuration
PRODUCT_NAME := xt_m31s
PRODUCT_DEVICE := m31s
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-M317F
PRODUCT_MANUFACTURER := samsung

TARGET_BOOT_ANIMATION_RES := 1080

## XT flags
INFINITY_MAINTAINER := XtrComSu
WITH_GAPPS := true
WITHOUT_RESERVED_SIZE := true
