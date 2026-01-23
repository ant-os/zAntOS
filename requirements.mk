include config.mk

MKBOOTIMG = $(DEVTOOLS_DIR)/mkbootimg

dev-tools = mkbootimg
static-deps = bootboot-loader

bootboot-loader: $(3RDP_DIR)/bootboot
	@make -C $(3RDP_DIR)/bootboot/$(ARCH)-$(FW_LOADER) all

$(MKBOOTIMG): 
	# @make -C $(3RDP_DIR)/bootboot/mkbootimg all
	unzip -o $(3RDP_DIR)/bootboot/mkbootimg-$(HOST_OS).zip mkbootimg -d devtools
	#cp $(3RDP_DIR)/bootboot/mkbootimg/mkbootimg $(DEVTOOLS_DIR)/mkbootimg


mkbootimg: $(MKBOOTIMG)
