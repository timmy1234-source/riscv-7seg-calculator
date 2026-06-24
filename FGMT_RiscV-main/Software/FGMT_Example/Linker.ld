/*
-----------------------------------------------------------------------------------------------
-- FGMT-RiscV: Implementation of 32-Bit Risc-V allowing fine grained multiprocessing
-- Copyright (C) 2025  Bernhard Lang
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, see http://www.gnu.org/licenses
-- or write to the Free Software Foundation,Inc., 51 Franklin Street,
-- Fifth Floor, Boston, MA 02110-1301  USA
-----------------------------------------------------------------------------------------------
*/

OUTPUT_ARCH( "riscv" )
ENTRY( entrypoint )

/* CODE_ORIGIN = 0x1480; */
CODE_ORIGIN = 0x2000;
CODE_SIZE   = 0x2000;
MEM_SIZE    = 0x1000;

MEMORY { 
  CODE (rx)  : ORIGIN = CODE_ORIGIN, LENGTH = CODE_SIZE
  DATA (rwx) : ORIGIN = CODE_ORIGIN + CODE_SIZE, LENGTH = MEM_SIZE
}

SECTIONS {
  __stack_size = DEFINED(__stack_size) ? __stack_size : 128;
  .vector_table : {
    KEEP (*(SORT_NONE(.vector_table)))
  } >CODE
  
  .text : {
    *(.text .text.*)
    *(.text*)
    *(.rodata .rodata.*)  
    *(.srodata .srodata.*)
  } >CODE
  . = ALIGN(4);
  PROVIDE (__etext = .);
  PROVIDE (_etext = .);
  PROVIDE (etext = .);

  _sidata = .;
  .data : AT( _sidata ) {
    _sdata = .;
    *(.rdata) 
    *(.data .data.*)
    *(.data*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
    _edata = .;
  }  >DATA
  PROVIDE( _edata = . );
  PROVIDE( edata = . );
  
  PROVIDE( _fbss = . );
  PROVIDE( __bss_start = . );
  .bss : {
    _sbss = .;
    *(.sbss*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } >DATA
  . = ALIGN(8);
  PROVIDE( _end = . );
  PROVIDE( end = . );
  
  .stack ORIGIN(DATA) + LENGTH(DATA) - __stack_size : {
    PROVIDE( _heap_end = . ); 
    . = __stack_size;  
    PROVIDE( _sp = . ); 
  } >DATA
  
}