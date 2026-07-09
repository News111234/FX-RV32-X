MEMORY {
  rom (rx) : ORIGIN = 0x00000000, LENGTH = 0x800
  ram (rw) : ORIGIN = 0x00000100, LENGTH = 0x700
}
SECTIONS {
  .text : { *(.text) } > rom
  .data : { *(.data) } > ram
}