ENTRY(AntkDriverEntry)

SECTIONS 
{
    .text ALIGN(0x1000) : {
        *(.text .text.* )
        *(.ltext .ltext.* )
    }
    .rodata ALIGN(0x1000): {
        *(.rodata .rodata.*)
        *(.lrodata .lrodata.*)
    }
    .data ALIGN(0x1000): {
        *(.data .data.*)
        *(.ldata .ldata.*)
    }
    .bss ALIGN(0x1000) (NOLOAD) : {
        *(.bss .bss.*)
        *(.lbss .lbss.*)
        *(COMMON)
    }

    /DISCARD/ : { *(.comment) }
}