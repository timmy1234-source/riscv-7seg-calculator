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
-- SpecialCmds
-- This pipeline stage handles the special commands LUI, AUIPC, JAL
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity SpecialCmds is
  generic (
    INST_ADDR_WIDTH : integer := 32;
    DATA_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  5
  );
  port (
    -- Input
    S_Valid    : in  std_logic;
    S_Ready    : out std_logic;
    S_PC       : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_ThNo     : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_Inst     : in  std_logic_vector(31 downto 0);
    -- Output for instructions lui, auipc, jal
    M_Valid    : out std_logic;
    M_Ready    : in  std_logic;
    M_PC       : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M_ThNo     : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_rdV      : out std_logic_vector(31 downto 0);
    M_rd       : out std_logic_vector(4 downto 0)
  );
end SpecialCmds;

library ieee;
use ieee.numeric_std.all;
architecture arch of SpecialCmds is
  constant Zeros : std_logic_vector(31 downto INST_ADDR_WIDTH) := (others => '0');
begin

  M_Valid    <= S_Valid;
  S_Ready    <= M_Ready;
  M_ThNo     <= S_ThNo;
  M_rd       <= S_Inst(11 downto 7); -- set destination register
  
  process(S_Valid,S_PC,S_Inst)
    variable JAL_sign_extend_imm20 : std_logic_vector(31 downto 0);
    variable PCtmp                 : unsigned(31 downto 0); 
  begin
    PCtmp := unsigned(S_PC) - to_unsigned(4,32);
    M_PC  <= (M_PC'range => '-');
    M_rdV <= (M_rdV'range => '-');
    if    S_Inst(6 downto 3)="0110" then
      -- LUI
      M_rdV <= S_Inst(31 downto 12) & "000000000000";
      M_PC  <= S_PC;                -- PC is already incremented by 4
    elsif S_Inst(6 downto 3)="0010" then
      -- AUIPC
      M_rdV <= std_logic_vector(PCtmp + unsigned(S_Inst(31 downto 12) & "000000000000"));
      M_PC       <= S_PC;                -- PC is already incremented by 4
    elsif S_Inst(6 downto 3)="1101" then
      -- JAL
      JAL_sign_extend_imm20(31 downto 20) := (31 downto 20 => S_Inst(31)); -- sign extend
      JAL_sign_extend_imm20(19 downto  1) := S_Inst(19 downto 12)&S_Inst(20)&S_Inst(30 downto 21);
      JAL_sign_extend_imm20(0)            := '0';
      M_rdV <= Zeros&S_PC;
      PCtmp := PCtmp + unsigned(JAL_sign_extend_imm20);
      M_PC  <= std_logic_vector(PCtmp(INST_ADDR_WIDTH-1 downto 0));
    elsif S_Valid='1' then
      M_PC  <= (M_PC'range => 'X');
      M_rdV <= (M_rdV'range => 'X');
    end if;
  end process;

end arch; -- SpecialCmds
