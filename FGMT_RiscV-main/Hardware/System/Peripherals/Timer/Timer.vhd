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

---------------------------------------------------------------------------------------------------
-- Timer-Komponente
-- Bernhard Lang
-- (c) Hochschule Osnabrueck
---------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Timer is
  generic ( N:integer );
  port (
    -- Prozessorbus
    CLK_I     : in    std_logic;
    RST_I     : in    std_logic;
    STB_I     : in    std_logic;
    WE_I      : in    std_logic;
    ADR_I     : in    std_logic_vector(4 downto 2);
    SEL_I     : in    std_logic_vector(3 downto 0);
    ACK_O     : out   std_logic;
    DAT_I     : in    std_logic_vector(31 downto 0);
    DAT_O     : out   std_logic_vector(31 downto 0);
    -- Ausgaenge
    Interrupt : out std_logic;
    PWM       : out std_logic
  );
  ------------------------------------------
  -- Address | Read         | Write        |
  ------------------------------------------
  --   00    | Periode      | Periode      |
  --   04    | Schwelle     | Schwelle     |
  --   08    | Zaehlerstand | Zaehlerstand |
  --   0C    | Kontroll     | Kontroll     | Bit 0: IrEn
  --   10    | Status       | Status       | Bit 0: IR_FF
  --   14    | -            | -            | 
  --   18    | -            | -            |
  --   1C    | -            | -            | 
  ------------------------------------------
end entity;

library ieee;
use ieee.numeric_std.all;

architecture behavioral of Timer is
  signal Schreibe_Schwelle : std_logic;
  signal Schreibe_Periode  : std_logic;
  signal Schreibe_Kontroll : std_logic;
  signal Lese_Status       : std_logic;
  signal IrEn              : std_logic;
  -- Register/FlipFlops
  signal IR_FF        : std_logic := '0';
  signal TC           : std_logic := '1';
  signal Periode      : std_logic_vector(N-1 downto 0):= (N-1 downto 0 => '0');
  signal Schwelle     : std_logic_vector(N-1 downto 0):= (N-1 downto 0 => '1'); 
  signal Zaehlerstand : std_logic_vector(N-1 downto 0):= (N-1 downto 0 => '0');
  signal Kontroll     : std_logic_vector(  1 downto 0):= (  1 downto 0 => '0');
  signal Status       : std_logic_vector(  0 downto 0);
begin

  Decoder: process(STB_I,ADR_I,SEL_I,WE_I)
  begin
    -- Default-Werte
    Schreibe_Periode  <= '0';
    Schreibe_Schwelle <= '0';
    Schreibe_Kontroll <= '0';
    Lese_Status       <= '0';
    ACK_O             <= STB_I;
    if STB_I='1'  then -- Wortzugriff gefordert
      if WE_I = '1' and SEL_I="1111" then -- Schreiben
        case ADR_I is
          when "000" => Schreibe_Periode  <= '1'; -- Periode
          when "001" => Schreibe_Schwelle <= '1'; -- Schwelle
          when "011" => Schreibe_Kontroll <= '1'; -- Kontroll
          when others  => null;
        end case;
      elsif WE_I = '0' then -- Lesen
        case ADR_I is
          when "100" => Lese_Status <= '1'; -- Status
          when others  => null;
        end case;
      end if;
    end if;
  end process;
  
  Lesedaten_MUX: process(ADR_I, Periode, Schwelle, Zaehlerstand, Kontroll, Status)
  begin
    DAT_O <= (DAT_O'range => '0');
    case ADR_I is
      when "000" => DAT_O(Periode'range)      <= Periode;
      when "001" => DAT_O(Schwelle'range)     <= Schwelle;
      when "010" => DAT_O(Zaehlerstand'range) <= Zaehlerstand;
      when "011" => DAT_O(Kontroll'range)     <= Kontroll;
      when "100" => DAT_O(Status'range)       <= Status;
      when others => null;
    end case;
  end process;

  REGs: process (CLK_I)
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        Periode  <= (Periode'range  => '0');
        Schwelle <= (Schwelle'range => '1'); -- initial auf maximalen Wert -> PWM='1'
        Kontroll <= (Kontroll'range => '0');
        IR_FF    <= '0';
      elsif RST_I /= '0' then
        Periode  <= (Periode'range  => 'X');
        Schwelle <= (Schwelle'range => 'X');
        Kontroll <= (Kontroll'range => 'X');
        IR_FF    <= 'X';
      else
        if Schreibe_Periode='1'  then Periode  <= DAT_I(Periode'range);  end if;
        if Schreibe_Schwelle='1' then Schwelle <= DAT_I(Schwelle'range); end if;
        if Schreibe_Kontroll='1' then Kontroll <= DAT_I(Kontroll'range); end if;
        if TC = '1'             then IR_FF <= '1';
        elsif Lese_Status = '1' then IR_FF <= '0';
        end if;
      end if;
    end if;
  end process;
  
  IrEn      <= Kontroll(0);
  
  Status(0) <= IR_FF;
  
  GenerateInt: process(IrEn, IR_FF) 
  begin
    if IrEn='1' then Interrupt <= IR_FF;
    else             Interrupt <= '0';
    end if;
  end process;
  
  Vergleicher: process(Schwelle, Zaehlerstand)
  begin
    if unsigned(Schwelle) > unsigned(Zaehlerstand) then PWM <= '1';
    else                                                PWM <= '0';
    end if;
  end process;
  
  Zaehler: process(CLK_I)
    variable Q : unsigned(Zaehlerstand'range) := (others => '0');
  begin
    if rising_edge(CLK_I) then
      if    RST_I = '1'     then Q := to_unsigned(0, Q'length);
      elsif Kontroll(1)='1' then Q := to_unsigned(0, Q'length);
      elsif TC = '1'        then Q := unsigned(Periode);
      else                       Q := Q - 1;
      end if;     
      if Q = 0 then  TC <= '1';
      else           TC <= '0';
      end if;
      Zaehlerstand <= std_logic_vector(Q);
    end if;
  end process;
  
end architecture;