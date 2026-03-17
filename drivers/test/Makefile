

build: 
	gcc -ffreestanding -Wl,-entry AntkDriverEntry -pie -Wl,-nostdlib -r -fno-PIE -mcmodel=large test.c -o ../../build/systemroot/test.drv -mno-red-zone 