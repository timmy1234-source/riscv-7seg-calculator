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
entity GPIO is
  generic (N: integer); -- Anzahl der GPIO-Bits
  port (
    CLK_I     : in    std_logic;
    RST_I     : in    std_logic;
    DAT_I     : in    std_logic_vector(31 downto 0);
    STB_I     : in    std_logic;
    ADR_I     : in    std_logic_vector(4 downto 2);
    SEL_I     : in    std_logic_vector(3 downto 0);
    WE_I      : in    std_logic;
    ACK_O     : out   std_logic;
    DAT_O     : out   std_logic_vector(31 downto 0);
    --
    Interrupt : out   std_logic;
    Pins      : inout std_logic_vector(N-1 downto 0)
  );
  ----------------------------
  -- Address | Read  | Write |
  --   00    | Pins  | -     |
  --   04    | DO    | DO    |
  --   08    | DIR   | DIR   |
  --   0C    | -     | -     |
  --   10    | IE_FF | IE_FF |
  --   14    | IP_FF | -     | 
  --   18    | IE_SF | IE_SF |
  --   1C    | IP_SF | -     | 
  ----------------------------
end GPIO;

architecture arch of GPIO is
  signal Schreibwert                                                    : std_logic_vector(N-1 downto 0);
  signal Lesewert_DI, Lesewert_DO, Lesewert_RI                          : std_logic_vector(N-1 downto 0);
  signal Lesewert_IE_FF, Lesewert_IP_FF, Lesewert_IE_SF, Lesewert_IP_SF : std_logic_vector(N-1 downto 0);
  signal Schreibe_RI, Schreibe_DO, Schreibe_IE_FF, Schreibe_IE_SF       : std_logic;
  signal Lese_IP_FF, Lese_IP_SF                                         : std_logic;
  signal DO, RI, DI, DI_delay, IE_FF, IE_SF, IP_FF, IP_SF               : std_logic_vector(N-1 downto 0);
begin

  ACK_O <= STB_I;

  Schreibwert <= DAT_I(N-1 downto 0);

  Schreibdekodierung: process(STB_I, WE_I, SEL_I, ADR_I)
    variable Wortzugriff: std_logic;
    variable Wort_schreiben: std_logic; 
  begin
    Schreibe_DO    <= '0';
    Schreibe_RI    <= '0';
    Schreibe_IE_FF <= '0';
    Schreibe_IE_SF <= '0';
    if STB_I='1' and SEL_I="1111" then Wortzugriff:= '1';
    else                               Wortzugriff:= '0';
    end if;
    Wort_schreiben := Wortzugriff and WE_I;
    case ADR_I is
      when "000" => null;
      when "001" => Schreibe_DO    <= Wort_schreiben;
      when "010" => Schreibe_RI    <= Wort_schreiben;
      when "011" => null;
      when "100" => Schreibe_IE_FF <= Wort_schreiben;
      when "101" => null;
      when "110" => Schreibe_IE_SF <= Wort_schreiben;
      when "111" => null;
      when others => null;
    end case;
  end process;
 
  Lesedekodierung: process(STB_I, WE_I, SEL_I, ADR_I)
    variable Wortzugriff: std_logic;
    variable Wort_lesen: std_logic; 
  begin
    Lese_IP_FF   <= '0';
    Lese_IP_SF   <= '0';
    if STB_I='1' and SEL_I="1111" then Wortzugriff:= '1';
    else                               Wortzugriff:= '0';
    end if;
    Wort_lesen := Wortzugriff and (not WE_I);
    case ADR_I is
      when "000" => null;
      when "001" => null;
      when "010" => null;
      when "011" => null;
      when "100" => null;
      when "101" => Lese_IP_FF <= Wort_Lesen;
      when "110" => null;
      when "111" => Lese_IP_SF <= Wort_Lesen;
      when others => null;
    end case;
  end process;
 
  Lesedatenmultiplexer: process(ADR_I, Lesewert_DI, Lesewert_DO, Lesewert_RI,
                                Lesewert_IE_FF, Lesewert_IP_FF, Lesewert_IE_SF, Lesewert_IP_SF)
  begin
    DAT_O <= (31 downto 0 => '0');
    case ADR_I is
      when "000" => DAT_O(N-1 downto 0) <= Lesewert_DI;
      when "001" => DAT_O(N-1 downto 0) <= Lesewert_DO;
      when "010" => DAT_O(N-1 downto 0) <= Lesewert_RI;
      when "011" => null;
      when "100" => DAT_O(N-1 downto 0) <= Lesewert_IE_FF;
      when "101" => DAT_O(N-1 downto 0) <= Lesewert_IP_FF;
      when "110" => DAT_O(N-1 downto 0) <= Lesewert_IE_SF;
      when "111" => DAT_O(N-1 downto 0) <= Lesewert_IP_SF;
      when others => null;
    end case;
  end process;

  GPIO_Register: process(CLK_I)
  begin
    if rising_edge(CLK_I) then
      if RST_I='1' then
        RI       <= (others=>'0');
        DO       <= (others=>'0');
        DI       <= (others=>'0');
        DI_delay <= (others=>'0');
        IE_FF    <= (others=>'0');
        IE_SF    <= (others=>'0');
        IP_FF    <= (others=>'0');
        IP_SF    <= (others=>'0');
      else
        if Schreibe_DO='1'    then DO    <= Schreibwert; end if;
        if Schreibe_RI='1'    then RI    <= Schreibwert; end if;
        if Schreibe_IE_FF='1' then IE_FF <= Schreibwert; end if;
        if Schreibe_IE_SF='1' then IE_SF <= Schreibwert; end if;
        DI       <= Pins;
        DI_delay <= DI;
        if Lese_IP_FF='1' then IP_FF <= (IP_FF'range => '0'); end if;
        if Lese_IP_SF='1' then IP_SF <= (IP_SF'range => '0'); end if;
        for i in IP_FF'range loop
           if DI(i)='0' and DI_Delay(i)='1' then IP_FF(i) <= '1'; end if;
        end loop;
        for i in IP_SF'range loop
           if DI(i)='1' and DI_Delay(i)='0' then IP_SF(i) <= '1'; end if;
        end loop;
      end if;
    end if;
  end process;
  Lesewert_DI    <= DI;
  Lesewert_DO    <= DO;
  Lesewert_RI    <= RI;
  Lesewert_IE_FF <= IE_FF;
  Lesewert_IE_SF <= IE_SF;
  Lesewert_IP_FF <= IP_FF;
  Lesewert_IP_SF <= IP_SF;
  
  TriState_Treiber: process(DO, RI)
  begin
    for i in RI'range loop
      if    RI(i)='1' then Pins(i)<= DO(i);
      elsif RI(i)='0' then Pins(i)<= 'Z';
      else                 Pins(i)<= 'X';
      end if;
    end loop;
  end process;
  
  Gen_Interrupt: process(IE_FF, IP_FF, IE_SF, IP_SF)
  begin
    Interrupt<='0';
    if (IE_FF and IP_FF) /= (N-1 downto 0 => '0') then Interrupt<='1'; end if;
    if (IE_SF and IP_SF) /= (N-1 downto 0 => '0') then Interrupt<='1'; end if;
  end process;
  
end arch;
