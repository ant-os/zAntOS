include config.mk

MEMORY_SIZE ?= 1G

# rom: initrd.rom
# 	qemu-system-x86_64 -option-rom ../dist/bootboot.bin -option-rom initrd.rom -serial stdio

#bios:
#	qemu-system-x86_64 -drive file=$(OUT_DIR)/$(OSNAME)-bios.img,format=raw -serial stdio

qemu-cd: dump-config dump-deps disk
	qemu-system-$(ARCH)  -bios $(OVMF) -cdrom $(OUT_DIR)/$(OSNAME)-$(FW_LOADER).img -s -display none -display none -serial mon:stdio -m 128M -net none -no-reboot -machine q35

# grubcdrom: grub.iso
# 	qemu-system-x86_64 -cdrom grub.iso -serial stdio

# grub2: grub.iso
#         qemu-system-x86_64 -drive file=disk-x86.img,format=raw -cdrom grub.iso -boot order=d -serial stdio

# efi:
#         qemu-system-x86_64 -bios $(OVMF) -m 64 -drive file=disk-x86.img,format=raw -serial stdio
#         @printf '\033[0m'

# eficdrom:
#         qemu-system-x86_64 -bios $(OVMF) -m 64 -cdrom disk-x86.img -serial stdio
#         @printf '\033[0m'

# linux:
#         qemu-system-x86_64 -kernel ../dist/bootboot.bin -drive file=disk-x86.img,format=raw -serial stdio

# sdcard:
#         qemu-system-aarch64 -M raspi3 -kernel ../dist/bootboot.img -drive file=disk-rpi.img,if=sd,format=raw -serial stdio

# riscv:
#         qemu-system-riscv64 -M microchip-icicle-kit -kernel ../dist/bootboot.rv64 -drive file=disk-icicle.img,if=sd,format=raw -serial stdio

# coreboot:
# ifeq ($(PLATFORM),x86)
#         qemu-system-x86_64 -bios coreboot-x86.rom -drive file=disk-x86.img,format=raw -serial stdio
# else
#         qemu-system-aarch64 -bios coreboot-arm.rom -M virt,secure=on,virtualization=on -cpu cortex-a53 -m 1024M -drive file=disk-rpi.img,format=raw -serial stdio
# endif

# bochs:
#bochs -f bochs.rc -q
