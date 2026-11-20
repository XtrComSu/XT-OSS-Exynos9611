#
# XT-OS product for Samsung Galaxy f41 (SM-F415F)
# Derived from Parbindar7/android_device_samsung_f41@lineage-24.0
#
# Two deltas vs the upstream lineage_f41.mk:
#   1. vendor/lineage -> vendor/infinity (Infinity X has no vendor/lineage)
#   2. PRODUCT_NAME lineage_f41 -> xt_f41, plus XT build flags
#

# NFC / device-specific toggles
TARGET_HAS_NFC := false

# Inherit device configuration
$(call inherit-product, device/samsung/f41/device.mk)
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
	BuildDesc="f41dd-user 12 SP1A.210812.016 F415FXXS2CVK1 release-keys" \
	BuildFingerprint="samsung/f41dd/f41:12/SP1A.210812.016/F415FXXS2CVK1:user/release-keys"

## Device configuration
PRODUCT_NAME := xt_f41
PRODUCT_DEVICE := f41
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-F415F
PRODUCT_MANUFACTURER := samsung

TARGET_BOOT_ANIMATION_RES := 1080

## XT flags
INFINITY_MAINTAINER := XtrComSu
WITH_GAPPS := false
WITHOUT_RESERVED_SIZE := true
