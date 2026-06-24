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
-- ErrorMUX
-- This component multiplexes the different error stream to one single stream and adds
-- an error ID 
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity ErrorMUX is
  generic (
    INST_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  3;
    ERR_ID_WIDTH    : integer :=  2
  );
  port (
    -- Input (1) from Instruction Alignment Error
    S_IA_Valid : in  std_logic;
    S_IA_Ready : out std_logic;
    S_IA_PC    : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_IA_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Input (2) from Data Alignment Error
    S_DA_Valid : in  std_logic;
    S_DA_Ready : out std_logic;
    S_DA_PC    : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_DA_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Input (3) from Unsupported Instruction Error
    S_UI_Valid : in  std_logic;
    S_UI_Ready : out std_logic;
    S_UI_PC    : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_UI_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Error Output
    Mx_Valid   : out std_logic;
    Mx_Ready   : in  std_logic;
    Mx_PC      : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    Mx_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    Mx_ErrID   : out std_logic_vector(ERR_ID_WIDTH-1 downto 0)
  );
end ErrorMUX;

library ieee;
use ieee.numeric_std.all;
architecture arch of ErrorMUX is
  signal IA_selected: std_logic;
  signal DA_selected: std_logic;
  signal UI_selected: std_logic;
begin
  -- prioritize inputs
  IA_selected <= S_IA_Valid;
  DA_selected <= S_DA_Valid and (not IA_selected);
  UI_selected <= S_UI_Valid and (not DA_selected);
  -- route Mx_Ready to selected input
  S_IA_Ready <= Mx_Ready when IA_selected='1' else '0';
  S_DA_Ready <= Mx_Ready when DA_selected='1' else '0';
  S_UI_Ready <= Mx_Ready when UI_selected='1' else '0';
  -- Multiplex Thread Infos to Error Output
  Mx_PC    <= S_IA_PC       when IA_selected='1' else
              S_DA_PC       when DA_selected='1' else
              S_UI_PC       when UI_selected='1' else
              (Mx_PC'range => '-');
  Mx_ThNo  <= S_IA_ThNo     when IA_selected='1' else
              S_DA_ThNo     when DA_selected='1' else
              S_UI_ThNo     when UI_selected='1' else
              (Mx_ThNo'range => '-');
  Mx_ErrID <= "01"          when IA_selected='1' else
              "10"          when DA_selected='1' else
              "11"          when UI_selected='1' else
              "00";
  Mx_Valid <= S_IA_Valid or S_DA_Valid or S_UI_Valid;
end arch;
