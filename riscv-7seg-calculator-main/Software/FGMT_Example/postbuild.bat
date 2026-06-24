@echo off
rem -----------------------------------------------------------------------------------------------
rem -- FGMT-RiscV: Implementation of 32-Bit Risc-V allowing fine grained multiprocessing
rem -- Copyright (C) 2025  Bernhard Lang
rem --
rem -- This program is free software; you can redistribute it and/or modify
rem -- it under the terms of the GNU General Public License as published by
rem -- the Free Software Foundation; either version 3 of the License, or
rem -- (at your option) any later version.
rem --
rem -- This program is distributed in the hope that it will be useful,
rem -- but WITHOUT ANY WARRANTY; without even the implied warranty of
rem -- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
rem -- GNU General Public License for more details.
rem --
rem -- You should have received a copy of the GNU General Public License
rem -- along with this program; if not, see http://www.gnu.org/licenses
rem -- or write to the Free Software Foundation,Inc., 51 Franklin Street,
rem -- Fifth Floor, Boston, MA 02110-1301  USA
rem -----------------------------------------------------------------------------------------------

set ProjName=%1

riscv-none-elf-objcopy -O ihex %ProjName%.elf %ProjName%.hex
riscv-none-elf-objdump -C -h -t -j.vector_table -j.text -j.data -j.bss -j.preinit_array -j.init_array -j.fini_array -S %ProjName%.elf > %ProjName%_diss.txt 
riscv-none-elf-objdump -C -h -j.vector_table -j.text -j.data -j.bss -j.preinit_array -j.init_array -j.fini_array %ProjName%.elf
