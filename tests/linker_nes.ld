MEMORY {
    HEADER (r) : ORIGIN = 0x7FF0, LENGTH = 0x0010
    ROM (rx) : ORIGIN = 0x8000, LENGTH = 0x3FFA
    VECTORS (r) : ORIGIN = 0xBFFA, LENGTH = 0x0006
    RAM (rw!x) : ORIGIN = 0x0200, LENGTH = 0x0600
}
SECTIONS {
    .inesheader : { KEEP(*(.inesheader)) } > HEADER
    .text : { *(.text) *(.text.*) } > ROM
    .rodata : { *(.rodata) *(.rodata.*) } > ROM
    .data : { *(.data) *(.data.*) } > RAM AT> ROM
    .bss : { *(.bss) *(.bss.*) } > RAM
    .nesvectors : { KEEP(*(.nesvectors)) } > VECTORS
}
