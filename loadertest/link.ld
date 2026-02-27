ENTRY(antkStartupSystem)


SECTIONS 
{
    . = 0xffffffff80000000;
    
    .text : { *(.text .text.* ) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }

    .bss (NOLOAD) : {
        . = ALIGN(16);
        *(.bss .bss.*)
        *(COMMON)
    }

    .moduledata ABSOLUTE(0xFFFFF00000000000) (NOLOAD) : {
        . = 0xFFFFF00000000000;
        __antboot_moduledata_start = .;
        . = 0xFFFFF01000000000;
        __antboot_moduledata_end = .;
    } 

    /DISCARD/ : { *(.eh_frame) *(.comment) }
}