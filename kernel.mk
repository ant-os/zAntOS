include config.mk

kernel: $(BUILD_DIR)/kernel
ktest: $(BUILD_DIR)/ktest

$(BUILD_DIR)/kernel: kernel/src/**
	make -C kernel all

$(BUILD_DIR)/ktest: kernel/src/**
	make -C kernel all

clean-kernel:
	@cd kernel
	@rm -rfv zig-cache || true
