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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
entity SevenSeg is 
  generic (
    Divider     : integer
  );
  port (
    CLK         : in  std_logic;
    --
    EN0         : in  std_logic;
    Digit0      : in  std_logic_vector(3 downto 0);	
    DP0         : in  std_logic;
    --
    EN1         : in  std_logic;
    Digit1      : in  std_logic_vector(3 downto 0);
    DP1         : in  std_logic;
    --
    EN2         : in  std_logic;
    Digit2      : in  std_logic_vector(3 downto 0);
    DP2         : in  std_logic;
    --
    EN3         : in  std_logic;
    Digit3      : in  std_logic_vector(3 downto 0);
    DP3         : in  std_logic;
    --
    DigitSelect : out std_logic_vector(3 downto 0);
    DigitBits   : out std_logic_vector(7 downto 0)
  );
  constant Divider_Bits : natural := integer(ceil(log2(real(Divider))));
end SevenSeg;

architecture arch of SevenSeg is
  function Bin_to_7Seg(Bin: std_logic_vector(3 downto 0); Enable: std_logic) return std_logic_vector is
    variable SevenSegBits: std_logic_vector(6 downto 0);
	begin
    if Enable='1' then
      case Bin is
        when x"0"   => SevenSegBits := "0111111"; -- 
        when x"1"   => SevenSegBits := "0000110"; -- Kodierung:
        when x"2"   => SevenSegBits := "1011011"; -- 
        when x"3"   => SevenSegBits := "1001111"; --    0000
        when x"4"   => SevenSegBits := "1100110"; --   5    1
        when x"5"   => SevenSegBits := "1101101"; --   5    1
        when x"6"   => SevenSegBits := "1111101"; --   5    1
        when x"7"   => SevenSegBits := "0000111"; --    6666
        when x"8"   => SevenSegBits := "1111111"; --   4    2
        when x"9"   => SevenSegBits := "1101111"; --   4    2
        when x"A"   => SevenSegBits := "1110111"; --   4    2
        when x"B"   => SevenSegBits := "1111100"; --    3333
        when x"C"   => SevenSegBits := "0111001"; -- 
        when x"D"   => SevenSegBits := "1011110"; -- Eine '1' bedeutet:
        when x"E"   => SevenSegBits := "1111001"; -- das Segment leuchtet
        when x"F"   => SevenSegBits := "1110001"; -- 
        when others => SevenSegBits := "XXXXXXX"; -- 
      end case;
    else SevenSegBits := "0000000";
    end if;
    return SevenSegBits;
	end function;
begin
  
  process (CLK)
		variable sel : integer range 0 to 3;
		variable cnt : unsigned(Divider_Bits-1 downto 0) := to_unsigned(0, Divider_Bits);
	begin
		if rising_edge(CLK) then
      -- Zaehler fuer Taktteiler und die Auswahl des Digits
      if cnt = Divider then
          cnt := to_unsigned(0, cnt'length);
          if sel>=3 then sel := 0; else sel := sel+1; end if;
      else 
          cnt := cnt+1;
      end if;
      -- Ansteuerung der Segmente
      case sel is 
          when 0 => DigitBits <= ((not EN0)or(not DP0)) & (not Bin_to_7Seg(Digit0, EN0));
          when 1 => DigitBits <= ((not EN1)or(not DP1)) & (not Bin_to_7Seg(Digit1, EN1));
          when 2 => DigitBits <= ((not EN2)or(not DP2)) & (not Bin_to_7Seg(Digit2, EN2));
          when 3 => DigitBits <= ((not EN3)or(not DP3)) & (not Bin_to_7Seg(Digit3, EN3));
      end case;   
      -- Auswahl des aktiven Segments
      DigitSelect      <= "1111";
      DigitSelect(sel) <= '0';
    end if;
	end process;

end arch;