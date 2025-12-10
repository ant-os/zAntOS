ifndef _MAKE_CONFIG_
_MAKE_CONFIG_ = 1
ARCH := x86_64
FW_LOADER := bios
OVMF := /usr/share/qemu/bios-TianoCoreEFI.bin
OSNAME := zAntOS
KERNEL_EXE := AntOSKrnl.bin
BUILD_DIR := build
OUT_DIR := output/$(ARCH)
INITRD_DIR = $(BUILD_DIR)/initrd
DEVTOOLS_DIR := devtools
3RDP_DIR := third-party

dump-config: 
	@echo Operating Sytem: $(OSNAME)
	@echo Architecture: $(ARCH)
	@echo Firmware Loader: $(FW_LOADER)
	@echo Kernel Image: $(KERNEL_EXE)
endif
