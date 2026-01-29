include ../config.mk

all: $(BUILD_DIR)/kernel

$(BUILD_DIR)/kernel: src/**
	zig build\
		-Doptimize=ReleaseFast --prefix ./ --prefix-exe-dir ../$(BUILD_DIR) 

clean:
	@cd kernel
	@rm -rfv zig-cache || true
