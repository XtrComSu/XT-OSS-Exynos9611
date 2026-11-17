#
# XT-OS product for Samsung Galaxy a51 (SM-A515F)
# Derived from Parbindar7/android_device_samsung_a51@lineage-24.0
#
# Two deltas vs the upstream lineage_a51.mk:
#   1. vendor/lineage -> vendor/infinity (Infinity X has no vendor/lineage)
#   2. PRODUCT_NAME lineage_a51 -> xt_a51, plus XT build flags
#

# NFC / device-specific toggles
TARGET_HAS_FOD := true
TARGET_HAS_UDFPS := true
TARGET_USES_NXP_NFC := true

# Inherit device configuration
$(call inherit-product, device/samsung/a51/device.mk)
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
	BuildDesc="a51nsxx-user 13 TP1A.220624.014 A515FXXU5GVK6 release-keys" \
	BuildFingerprint="samsung/a51nsxx/a51:13/TP1A.220624.014/A515FXXU5GVK6:user/release-keys"

## Device configuration
PRODUCT_NAME := xt_a51
PRODUCT_DEVICE := a51
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-A515F
PRODUCT_MANUFACTURER := samsung

TARGET_BOOT_ANIMATION_RES := 1080

## XT flags
INFINITY_MAINTAINER := XtrComSu
WITH_GAPPS := true
WITHOUT_RESERVED_SIZE := true
