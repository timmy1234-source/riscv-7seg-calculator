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

// -------------------------------------------------------------------------------------------------
//  Control Register (CR):
//   15..0  : Bitbreite - 1
//   19..16 : Anzahl Datenbits - 1
//   20     : Paritaet ein
//   21     : Paritaet gerade
//   23..22 : Stoppbits
//            00: 1.0 Stoppbits
//            01: 1.5 Stoppbits
//            10: 2.0 Stoppbits
//            11: 2.5 Stoppbits
//   24     : Freigabe fuer Empfangs-Interrupt
//   25     : Freigabe fuer Sende-Interrupt
// -------------------------------------------------------------------------------------------------
//  Status Register (SR):
//   0      : Daten liegen im Empfangspuffer
//   1      : Sendepuffer ist frei
//   2      : Ueberlauf (wird beim Lesen geloescht)
// -------------------------------------------------------------------------------------------------

#include <stdint.h>

#define UART_TDR 0x0
#define UART_RDR 0x4
#define UART_CR  0x8
#define UART_SR  0xC

#define UART_RX_AVAIL (1<<0)
#define UART_TX_EMPTY (1<<1)
#define UART_RX_IR (1<<24)
#define UART_TX_IR (1<<25)

#define RX_BUFFER_SIZE 40
#define TX_BUFFER_SIZE 40

#define PARITY_NONE  0x0
#define PARITY_ODD   0x2
#define PARITY_EVEN  0x3
#define STOPPBITS_10 0x0
#define STOPPBITS_15 0x1
#define STOPPBITS_20 0x2
#define STOPPBITS_25 0x3

void UART_Init(uint32_t baudrate, uint32_t bits, uint32_t parity, uint32_t stoppbits);

int outbyte(unsigned char);
int inbyte(unsigned char*);
