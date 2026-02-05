# old makefile-based config

ifndef _MAKE_CONFIG_
_MAKE_CONFIG_ = 1
ARCH := x86_64
FW_LOADER := efi
OVMF := /usr/share/qemu/OVMF.fd
OSNAME := zAntOS
KERNEL_EXE := AntOSKrnl.bin
BUILD_DIR := build
OUT_DIR := output/$(ARCH)
INITRD_DIR = $(BUILD_DIR)/initrd
DEVTOOLS_DIR := devtools
3RDP_DIR := third-party
HOST_OS := Linux
dump-config: 
	@echo Operating System: $(OSNAME)
	@echo Architecture: $(ARCH)
	@echo Firmware Loader: $(FW_LOADER)
	@echo Kernel Image File: $(KERNEL_EXE)

endif
