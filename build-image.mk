include config.mk
include requirements.mk

INITRD_DIRS = $(INITRD_DIR)

all: dump-deps disk rom

ifneq ($(ARCH), x86-64)
	$(error Unsupported architecture $(ARCH))
endif

kernel: 
	$(MKBOOTIMG) check $(BUILD_DIR)/kernel

# create an initial ram disk image with the kernel inside
initrd: kernel
		@mkdir -pv $(INITRD_DIRS)
		@cp -v $(BUILD_DIR)/kernel $(INITRD_DIR)/$(KERNEL_EXE)

# create hybrid disk / cdrom image or ROM image
disk: $(MKBOOTIMG) initrd mkbootimg.json
		$(MKBOOTIMG) mkbootimg.json $(OUT_DIR)/$(OSNAME)-$(FW_LOADER).img

rom: $(MKBOOTIMG) initrd mkbootimg.json
		$(MKBOOTIMG) mkbootimg.json $(OUT_DIR)/$(OSNAME)-$(FW_LOADER).rom

dump-deps: 
	@echo Build-time Tools: $(dev-tools)
	@echo "Runtime Dependencies (Static): $(static-deps)"

# create a GRUB cdrom
# grub.iso: ../mkbootimg/mkbootimg initdir mkbootimg.json
#         @../mkbootimg/mkbootimg mkbootimg.json initrd.bin
#         @rm -rf initrd
#         @mkdir iso iso/bootboot iso/boot iso/boot/grub 2>/dev/null || true
#         @cp ../dist/bootboot.bin iso/bootboot/loader || true
#         @cp config iso/bootboot/config || true
#         @cp initrd.bin iso/bootboot/initrd || true
#         @printf "menuentry \"BOOTBOOT test\" {\n  multiboot /bootboot/loader\n  module /bootboot/initrd\n  module /bootboot/config\n  boot\n}\n\nmenuentry \"Chainload\" {\n  set root=(hd0)\n  chainloader +1\n  boot\n}\n" >iso/boot/grub/grub.cfg || true
#         grub-mkrescue -o grub.iso iso
#         @rm -r iso 2>/dev/null || true
