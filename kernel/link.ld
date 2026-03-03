ENTRY(antkStartupSystem)

__bootldr_canary = 0x74325f656e747279;

SECTIONS 
{
    

    . = 0xffffffff80000000;
    __kernel_start = .;
    
    .text ALIGN(0x1000) : {
        *(.text .text.* )
    }
    .rodata ALIGN(0x1000): {
        *(.rodata .rodata.*)
    }
    .data ALIGN(0x1000): {
        *(.data .data.*)
    }

    .bss ALIGN(0x1000) (NOLOAD) : {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ : { *(.eh_frame*) *(.comment) }
}