OUTPUT_ARCH( "riscv" )
ENTRY( _main )


SECTIONS
{
 . = 0x0;
 
  .text : {
    *(.text .text.*)
  }

  .rodata : ALIGN(4k) {
    . = ALIGN(16);
    *(.srodata .srodata.*) /* do not need to distinguish this from .rodata */
    . = ALIGN(16);
    *(.rodata .rodata.*)
    . = ALIGN(0x1000);
    __debug_info_start = .;
    KEEP(*(.debug_info))
    __debug_info_end = .;
    __debug_abbrev_start = .;
    KEEP(*(.debug_abbrev))
    __debug_abbrev_end = .;
    __debug_str_start = .;
    KEEP(*(.debug_str))
    __debug_str_end = .;
    __debug_line_start = .;
    KEEP(*(.debug_line))
    __debug_line_end = .;
    __debug_ranges_start = .;
    KEEP(*(.debug_ranges))
    __debug_ranges_end = .;
  }

  .data : ALIGN(4k) {
    . = ALIGN(16);
    *(.sdata .sdata.*) /* do not need to distinguish this from .data */
    . = ALIGN(16);
    *(.data .data.*)
  }

  .bss : ALIGN(4k) {
    . = ALIGN(16);
    *(.sbss .sbss.*) /* do not need to distinguish this from .bss */
    . = ALIGN(16);
    *(.bss .bss.*)
  }

  PROVIDE(end = .);
}
