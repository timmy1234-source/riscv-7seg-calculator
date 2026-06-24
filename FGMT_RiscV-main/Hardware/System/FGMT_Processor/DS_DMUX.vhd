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
-- DS_DMUX
-- Demultiplex input S to output M0 when S_ThNo=0, else to M1
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity DS_DMUX is
  generic (
    ADR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    -- Input
    S_Valid  : in  std_logic;
    S_Ready  : out std_logic;
    S_PC     : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output (0) 
    M0_Valid : out std_logic;
    M0_Ready : in  std_logic;
    M0_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M0_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output (1) 
    M1_Valid : out std_logic;
    M1_Ready : in  std_logic;
    M1_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M1_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end DS_DMUX;

library ieee;
use ieee.numeric_std.all;
architecture arch of DS_DMUX is
begin

  M0_PC   <= S_PC;
  M0_ThNo <= S_ThNo;
  M1_PC   <= S_PC;
  M1_ThNo <= S_ThNo;

  process(S_Valid, S_ThNo, M0_Ready, M1_Ready)
  begin
    if unsigned(S_ThNo)=0 then
      M0_Valid <= S_Valid;
      M1_Valid <= '0';
      S_Ready  <= M0_Ready;
    else 
      M0_Valid <= '0';
      M1_Valid <= S_Valid;
      S_Ready  <= M1_Ready;
    end if;
  end process;
end arch;
