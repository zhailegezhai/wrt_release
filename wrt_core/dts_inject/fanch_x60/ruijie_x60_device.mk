
# Injected: Ruijie RG-X60 (non-Pro, MT7986A, Airoha EN8811H WAN PHY)
define Device/ruijie_rg-x60
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X60
  DEVICE_DTS := mt7986a-ruijie-rg-x60
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-phy-airoha-en8811h
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x60
