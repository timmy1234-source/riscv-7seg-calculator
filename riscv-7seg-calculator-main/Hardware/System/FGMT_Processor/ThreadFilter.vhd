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
-- ThreadFilter
-- The ThreadFilter is able to route Thread-Tokens to the Debug Interface when
-- corresponding TF_ThBits are set.
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
entity ThreadFilter is
  generic (
    ADR_WIDTH       : integer := 13; -- Values in range 32..13
    THREAD_NO_WIDTH : integer :=  3
  );
  port(
    CLK       : in  std_logic;
    RESET     : in  std_logic;
    -- Controls
    TF_ThBits : in  std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    -- Input
    S_Valid   : in  std_logic;
    S_Ready   : out std_logic;
    S_PC      : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo    : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output
    DBG_Valid : out std_logic;
    DBG_Ready : in  std_logic;
    DBG_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    DBG_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output
    M_Valid   : out std_logic;
    M_Ready   : in  std_logic;
    M_PC      : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end ThreadFilter;

library IEEE;
use IEEE.numeric_std.all;
architecture arch of ThreadFilter is
begin
  
  process(S_Valid, TF_ThBits, DBG_Ready, M_Ready, S_ThNo)
  begin
    DBG_Valid <= '0';
    M_Valid   <= '0';
    S_Ready   <= '0';
    if (S_Valid='1') then
      if TF_ThBits(to_integer(unsigned(S_ThNo)))='1' then
        DBG_Valid <= '1';
        S_Ready   <= DBG_Ready;
      else
        M_Valid   <= '1';
        S_Ready   <= M_Ready;
      end if;
    end if;
  end process;
  
  DBG_PC   <= S_PC;
  DBG_ThNo <= S_ThNo;
  M_PC     <= S_PC;
  M_ThNo   <= S_ThNo;
  
end arch;