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

-------------------------------------------------------------------------------
-- Serieller Sender
-------------------------------------------------------------------------------
-- Modul Digitale Komponenten
-- Hochschule Osnabrueck
-- Bernhard Lang, Rainer Hoeckmann
-------------------------------------------------------------------------------
-- BitBreiteM1 = (Taktfrequenz / Baudrate) - 1
--
-- Bits = AnzahlBits - 1
--
-- Kodierung Stoppbits:
--   00 - 1   Stoppbits
--   01 - 1,5 Stobbits
--   10 - 2   Stoppbits
--   11 - 2,5 Stoppbits
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Serieller_Sender is
	generic(
		DATA_WIDTH  	  	: positive;
		BITBREITE_WIDTH 	: positive;
		BITS_WIDTH		  	: positive
	);	
	port(	
		Takt			  	  : in  std_logic;
		Reset           : in  std_logic;

		BitBreiteM1 		: in  std_logic_vector(BITBREITE_WIDTH - 1 downto 0);
		BitsM1 		  	  : in  std_logic_vector(BITS_WIDTH - 1 downto 0);
		Paritaet_ein	  : in  std_logic;
		Paritaet_gerade	: in  std_logic;
		Stoppbits		  	: in  std_logic_vector(1 downto 0);

		S_Valid			    : in  std_logic;
		S_Ready			    : out std_logic;
		S_Data			  	: in  std_logic_vector(DATA_WIDTH - 1 downto 0);

		TxD				  	  : out std_logic
	);
end entity;

architecture rtl of Serieller_Sender is	
	
	-- Typ fuer die Ansteuerung des Multiplexers
	type TxDSel_type is (D, P, H, L);

	-- Signale zwischen Steuerwerk und Rechenwerk
	signal TxDSel    : TxDSel_type := H;
	signal ShiftEn   : std_logic;
	signal ShiftLd   : std_logic;
	signal CntSel    : std_logic := '-';
	signal CntEn     : std_logic;
	signal CntLd     : std_logic;
	signal CntTc     : std_logic := '1';
	signal BBSel     : std_logic := '0';
	signal BBLd      : std_logic;
	signal BBTC      : std_logic := '0';
	
begin
	Rechenwerk: block
	    -- Interne Signale des Rechenwerks
		signal DataBit   : std_logic := '0';
		signal ParityBit : std_logic := '0';
	begin
		-- Schieberegister zur Aufnahme der Sendedaten
		Schieberegister: process(Takt)
			variable Q : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others=>'0');
		begin
			if rising_edge(Takt) then
				if Reset = '1' then
					Q := (others=>'0');
				else
					if    ShiftLd = '1' then Q := S_Data;
					elsif ShiftEn = '1' then Q := '0' & Q(DATA_WIDTH - 1 downto 1);
					end if;
				end if;
				DataBit <= Q(0);							
			end if;			
		end process;
		
		-- Register fuer das Paritaetsbit
		FF: process(Takt)
			variable parity : std_logic := '0';
		begin
			if rising_edge(Takt) then
				if Reset = '1' then
					ParityBit <= '0';
				else					
					if ShiftLd = '1' then
						parity := not Paritaet_gerade;
						for i in S_Data'range loop
							if i <= unsigned(BitsM1) then
								parity := parity xor S_Data(i);
							end if;
						end loop;
					end if;									
					ParityBit <= parity;
				end if;				
			end if;
		end process;
		
		-- Zaehler Bits und Stoppbits
		ZaehlerBits: process(Takt)
			variable Q : unsigned(BITS_WIDTH - 1 downto 0) := (others=>'0');
		begin
			if rising_edge(Takt) then
				if Reset = '1' then
					Q := (others=>'0');
				else
					if CntLd = '1' then
						if CntSel = '0' then
							Q := unsigned(BitsM1);
						elsif CntSel = '1' then
							Q(BITS_WIDTH - 1 downto Stoppbits'High + 1) := (others=>'0');
							Q(Stoppbits'High downto Stoppbits'Low)      := unsigned(Stoppbits);
						end if;
					elsif CntEn = '1' then
						Q := Q - 1;
					end if;
				end if;
				if Q = 0 then CntTc <= '1';
				else 					CntTc <= '0'; 
				end if;				
			end if;
		end process;
		
		-- Zaehler Bitbreite
		ZaehlerBitbreite: process(Takt)
			variable Q : unsigned(BITBREITE_WIDTH - 1 downto 0) := (others=>'0');
		begin
			if rising_edge(Takt) then
				if Reset = '1' then
					Q := (others=>'0');
				else
					if BBLd = '1' or BBTC = '1' then
						if    BBSel = '0' then Q := unsigned(BitBreiteM1);
						elsif BBSel = '1' then Q := unsigned('0' & BitBreiteM1(BITBREITE_WIDTH-1 downto 1));
						end if;
					else
						Q := Q - 1;
					end if;
				end if;
				if Q = 0 then BBTC <= '1';
				else 					BBTC <= '0'; 
				end if;				
			end if;
		end process;
		
		-- Ausgangsmultiplexer
		OutMux: process(TxDSel, DataBit, ParityBit)
		begin
			case TxDSel is
				when D => TxD <= DataBit;
				when P => TxD <= ParityBit;
				when H => TxD <= '1';
				when L => TxD <= '0';
			end case;			
		end process;

	end block;
	
	Steuerwerk: block
		-- Typ fuer die Zustandswerte
		type Zustand_type is (Z_IDLE, Z_START, Z_BITS, Z_PARI, Z_STP, Z_ERROR);
    -- Interne Signale des Rechenwerks
		signal Zustand      : Zustand_type := Z_IDLE;
		signal Folgezustand : Zustand_type;		
		-- Internes Signal fuer die Initialisierung
		signal S_Ready_i    : std_logic := '1';
	begin	
		-- Wert des internen Signals an Port zuweisen	
		S_Ready <= S_Ready_i;

		-- Prozess zur Berechnung des Folgezustands und der Mealy-Ausgaenge
		Transition: process(Zustand, S_Valid, BBTC, CntTC, Paritaet_ein)
		begin
			-- Default-Werte fuer den Folgezustand und die Mealy-Ausgaenge
			ShiftEn      <= '0'; 
			ShiftLd      <= '0'; 
			CntEn        <= '0'; 
			CntLd        <= '0'; 
			BBLd         <= '0';
			Folgezustand <= Z_ERROR;
			-- Berechnung des Folgezustands und der Mealy-Ausgaenge
			case Zustand is
				when Z_IDLE  =>
					if S_Valid = '0' then
						Folgezustand <= Z_IDLE;
					elsif S_Valid = '1' then
						Folgezustand <= Z_START;
						ShiftLd      <= '1'; 
						BBLd         <= '1';
					end if;
				when Z_START =>
					if BBTC = '0' then
						Folgezustand <= Z_START;
					elsif BBTC = '1' then
						Folgezustand <= Z_BITS;
						CntLd        <= '1';
					end if;
				when Z_BITS  =>
					if BBTC = '0' then
						Folgezustand <= Z_BITS;
					elsif BBTC = '1' then
						if CntTC = '0' then
							Folgezustand <=  Z_BITS;
							CntEn        <= '1';
							ShiftEn      <= '1';
						elsif CntTC = '1' then
							if Paritaet_ein = '0' then
								Folgezustand <= Z_STP;
								CntLd        <= '1';
							elsif Paritaet_ein = '1' then
								Folgezustand <= Z_PARI;								
							end if;						
						end if;					
					end if;
				when Z_PARI  =>
					if BBTC = '0' then
						Folgezustand <= Z_PARI;
					elsif BBTC = '1' then
						Folgezustand <= Z_STP;
						CntLd        <= '1';
					end if;
				when Z_STP   =>
					if BBTC = '0' then
						Folgezustand <= Z_STP;
					elsif BBTC = '1' then
						if CntTC = '0' then
							Folgezustand <= Z_STP;
							CntEn <= '1';
						elsif CntTC = '1' then
							Folgezustand <= Z_IDLE;
						end if;
					end if;
				when Z_ERROR =>
					-- synthesis translate off
					report "Serieller_Sender erreicht Fehlerzustand" severity failure;
					-- synthesis translate on
					null;
			end case;
		end process;
		
		-- Register fuer Zustand und Moore-Ausgaenge
		Reg: process(Takt)
		begin
			if rising_edge(Takt) then
				-- Zustandsregister
				if Reset = '1' then	Zustand <= Z_IDLE;
				else      					Zustand <= Folgezustand;
				end if;
				-- Berechnung der Moore-Ausgaenge aus dem Folgezustand
				if Reset = '1' then
					S_Ready_i <= '1'; TxDSel  <= H; CntSel  <= '-'; BBSel   <= '0';
				else
					case Folgezustand is
						when Z_IDLE  => S_Ready_i <= '1'; TxDSel  <= H; CntSel  <= '-'; BBSel   <= '0';
						when Z_START => S_Ready_i <= '0'; TxDSel  <= L; CntSel  <= '0'; BBSel   <= '0';
						when Z_BITS  => S_Ready_i <= '0'; TxDSel  <= D; CntSel  <= '1'; BBSel   <= '0';
						when Z_PARI  => S_Ready_i <= '0'; TxDSel  <= P; CntSel  <= '1'; BBSel   <= '0';
						when Z_STP   => S_Ready_i <= '0'; TxDSel  <= H; CntSel  <= '-'; BBSel   <= '1';
						when Z_ERROR => S_Ready_i <= '0'; TxDSel  <= H; CntSel  <= '-'; BBSel   <= '-';
					end case;
				end if;
			end if;
		end process;
			
	end block;
end architecture;