include config.mk

kernel: $(BUILD_DIR)/kernel

$(BUILD_DIR)/kernel: kernel/src/**
	make -C kernel all

clean-kernel:
	@cd kernel
	@rm -rfv zig-cache || true
