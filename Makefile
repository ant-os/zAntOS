include config.mk
include kernel.mk
include build-image.mk
include runners.mk

SETUP_DIRS = $(BUILD_DIR) $(OUT_DIR) $(DEVTOOLS_DIR)
setup: 
	@rm -Rdvf $(SETUP_DIRS)
	@mkdir -vp $(SETUP_DIRS)

clean: clean-kernel
	@rm -rfv $(BUILD_DIR)/* 2>/dev/null || true
