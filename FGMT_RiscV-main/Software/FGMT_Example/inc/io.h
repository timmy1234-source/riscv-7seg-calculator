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

#pragma once

void out32(unsigned addr, unsigned data);
unsigned in32(unsigned addr);

unsigned bit_of(unsigned Value, unsigned Bitnum);
unsigned read_bit(unsigned addr, unsigned Bitnum);
void set_bit(unsigned addr, unsigned Bitnum);
void clear_bit(unsigned addr, unsigned Bitnum);
unsigned read_bitfield(unsigned addr, unsigned Mask, unsigned Shift);
void write_bitfield(unsigned addr, unsigned Value, unsigned Mask, unsigned Shift);
