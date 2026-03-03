ENTRY(antkStartupSystem)

SECTIONS 
{
    . = 0xffffffff80000000;
    
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