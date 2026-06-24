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

//----------------------------------------------------
// Wishbone Adresses of the Debugging Peripherals
//----------------------------------------------------

#include "io.h"

// Launcher
#define LAUNCHER_BASE 0xffffffe0
#define LAUNCHER_STATUS 0x00
#define LAUNCHER_THREAD 0x04
#define LAUNCHER_PC     0x08
#define LAUNCHER_THNO   0x0C

//----------------------------------------------------
// Macros for generating injection commands
//----------------------------------------------------
#define LUI(rd,value)       ( 0x00000037 | ((value)&0xfffff000)  | ((rd&0x1f)<<7) )
#define ADDI(rd,rs1,value)  ( 0x00000013 | (((value)&0xfff)<<20) | ((rs1&0x1f)<<15) | ((rd&0x1f)<<7) )
#define JALR(rd,offset,rs1) ( 0x00000067 | (((offset)&0xfff)<<20) | ((rs1&0x1f)<<15) | ((rd&0x1f)<<7) )

#define SP (2)

unsigned int startup_code[7];
void riscv_Launch(void* pc, unsigned int thread, void* stack) {
  unsigned int value; 
  // setup stack pointer
  value = (unsigned int) stack;
  startup_code[0] = (0<(value&0x800)) ? LUI(SP,value+0x1000) : LUI(SP,value);
  startup_code[1] = ADDI(SP,SP,value);
  // load thread start address into register 1
  value = (unsigned int) pc;
  startup_code[2] = (0<(value&0x800)) ? LUI(1,value+0x1000) : LUI(1,value);
  startup_code[3] = ADDI(1,1,value);
  // Call thread
  startup_code[4] = JALR(1,0,1);
  // On thread return jump to 0xfffffffc to terminate thread
  startup_code[5] = JALR(0,0xfffffffc,0);
  do {
    out32(LAUNCHER_BASE+LAUNCHER_THREAD,0);                // Launcher mit eigener ThId belegen (Versuch)
    // Wenn Belegen erfolgreich war, dann muss Bit0 im Status-Register zu 1 gesetzt sein
    if (1==(in32(LAUNCHER_BASE+LAUNCHER_STATUS)&1)) { break; } // Thread hat es geschafft den Launcher zu belegen
  } while (1);
  // out32(LAUNCHER_BASE+LAUNCHER_PC,(unsigned int) pc);  // pc zum Launchen setzen
  out32(LAUNCHER_BASE+LAUNCHER_PC,(unsigned int) startup_code);
  out32(LAUNCHER_BASE+LAUNCHER_THNO,thread);           // thread setzen und Token launchen
  for (volatile int i=0; i<5; i++) { /* wait some time that the thread can launch */ }
}


