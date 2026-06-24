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

---------------------------------------------------------------------------------------
-- DS_SMUX2, DS_SMUX3
-- This are simple datastream multiplexers.
-- They do *not* guarantee stable "M_PC" and "M_ThNo" outputs when
-- "(M_Valid='1') and (M_Ready='0')". It can be used when the next element
-- in this case does not rely on stable data inputs, e.g. DS_DataSync or DS_Fifo.
-- The inputs are prioritized. S0 has priority over S1 and so on.
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity DS_SMUX2 is
  generic (
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    -- Input (0) highest priority
    S0_Valid : in  std_logic;
    S0_Ready : out std_logic;
    S0_PC    : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S0_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Input (1) lowest priority
    S1_Valid : in  std_logic;
    S1_Ready : out std_logic;
    S1_PC    : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S1_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output
    M_Valid  : out std_logic;
    M_Ready  : in  std_logic;
    M_PC     : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end DS_SMUX2;

architecture arch of DS_SMUX2 is
begin
  process(S0_Valid, S0_PC, S0_ThNo,
          S1_Valid, S1_PC, S1_ThNo,
          M_Ready)
  begin
    S0_Ready <= '0';
    S1_Ready <= '0';
    M_Valid  <= '0';
    M_PC     <= (M_PC'range   => '-');
    M_ThNo   <= (M_ThNo'range => '-');
    if S0_Valid='1' then
      M_Valid  <= S0_Valid;
      M_PC     <= S0_PC;
      M_ThNo   <= S0_ThNo;
      S0_Ready <= M_Ready;
    elsif S1_Valid='1' then
      M_Valid  <= S1_Valid;
      M_PC     <= S1_PC;
      M_ThNo   <= S1_ThNo;
      S1_Ready <= M_Ready;
    end if;
  end process;
end arch;

library ieee;
use ieee.std_logic_1164.all;
entity DS_SMUX3 is
  generic (
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    -- Input (0) highest priority
    S0_Valid : in  std_logic;
    S0_Ready : out std_logic;
    S0_PC    : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S0_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Input (1) medium priority
    S1_Valid : in  std_logic;
    S1_Ready : out std_logic;
    S1_PC    : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S1_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Input (2) lowest priority
    S2_Valid : in  std_logic;
    S2_Ready : out std_logic;
    S2_PC    : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S2_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output
    M_Valid  : out std_logic;
    M_Ready  : in  std_logic;
    M_PC     : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end DS_SMUX3;

architecture arch of DS_SMUX3 is
begin
  process(S0_Valid, S0_PC, S0_ThNo,
          S1_Valid, S1_PC, S1_ThNo,
          S2_Valid, S2_PC, S2_ThNo,
          M_Ready)
  begin
    S0_Ready <= '0';
    S1_Ready <= '0';
    S2_Ready <= '0';
    M_Valid  <= '0';
    M_PC     <= (M_PC'range   => '-');
    M_ThNo   <= (M_ThNo'range => '-');
    if S0_Valid='1' then
      M_Valid  <= S0_Valid;
      M_PC     <= S0_PC;
      M_ThNo   <= S0_ThNo;
      S0_Ready <= M_Ready;
    elsif S1_Valid='1' then
      M_Valid  <= S1_Valid;
      M_PC     <= S1_PC;
      M_ThNo   <= S1_ThNo;
      S1_Ready <= M_Ready;
    elsif S2_Valid='1' then
      M_Valid  <= S2_Valid;
      M_PC     <= S2_PC;
      M_ThNo   <= S2_ThNo;
      S2_Ready <= M_Ready;
    end if;
  end process;
end arch;