//---------------------------------------------------------------------------------------------
// FGMT-RiscV: Implementation of 32-Bit Risc-V allowing fine grained multiprocessing
// Copyright (C) 2025  Bernhard Lang
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, see http://www.gnu.org/licenses
// or write to the Free Software Foundation,Inc., 51 Franklin Street,
// Fifth Floor, Boston, MA 02110-1301  USA
//---------------------------------------------------------------------------------------------

#include <stdint.h>
#include <string.h>


int main();

// Pre-defined memory locations for program initialization.
extern uint32_t _sidata, _sdata, _edata, _sbss, _ebss;

void premain() {
  uint8_t *src, *dst;

  // Copy initialized data from .sidata (Flash) to .data (RAM)
  src = (uint8_t *)&_sidata;
  dst = (uint8_t *)&_sdata;
  while (dst < (uint8_t *)&_edata)
      *dst++ = *src++;

  // Clear the .bss RAM section.
  dst = (uint8_t *)&_sbss;
  while (dst < (uint8_t *)&_ebss)
      *dst++ = 0;

  main();
  
  while(1) {}
}
