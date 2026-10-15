MEMORY {
  flash_text (rx) : ORIGIN = 0x0200, LENGTH = 14K
  flash_rodata (r) : ORIGIN = 0x4000, LENGTH = 4K
  ram (rw!x) : ORIGIN = 0x805000, LENGTH = 4K
}

SECTIONS {
  .text : {
    *(.text*)
  } > flash_text

  .rodata : {
    *(.rodata*)
  } > flash_rodata

  .data : {
    *(.data*)
  } > ram AT > flash_rodata

  .bss : {
    *(.bss*)
  } > ram
}
