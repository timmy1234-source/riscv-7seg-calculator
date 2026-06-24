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
-- FunctionDMUX
-- This pipeline stage routes the instructions either to the computation block
-- or to the block to access memeory  
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity FunctionDMUX is
  generic (
    INST_ADDR_WIDTH : integer := 32;
    DATA_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    -- Input
    S_Valid  : in  std_logic;
    S_Ready  : out std_logic;
    S_PC     : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_Imm12  : in  std_logic_vector(11 downto 0);
    S_rs1V   : in  std_logic_vector(31 downto 0);
    S_rs2V   : in  std_logic_vector(31 downto 0);
    S_rd     : in  std_logic_vector( 4 downto 0);
    S_cmd    : in  std_logic_vector(10 downto 0);
    -- Output for Register Commands
    M0_Valid : out std_logic;
    M0_Ready : in  std_logic;
    M0_PC    : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M0_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M0_Imm12 : out std_logic_vector(11 downto 0);
    M0_rs1V  : out std_logic_vector(31 downto 0);
    M0_rs2V  : out std_logic_vector(31 downto 0);
    M0_rd    : out std_logic_vector( 4 downto 0);
    M0_cmd   : out std_logic_vector(10 downto 0);
    -- Output for Data Memory Load/Store
    M1_Valid : out std_logic;
    M1_Ready : in  std_logic;
    M1_PC    : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M1_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M1_Imm12 : out std_logic_vector(11 downto 0);
    M1_rs1V  : out std_logic_vector(31 downto 0);
    M1_rs2V  : out std_logic_vector(31 downto 0);
    M1_rd    : out std_logic_vector( 4 downto 0);
    M1_cmd   : out std_logic_vector(10 downto 0);
    -- Error Output
    Mx_Valid : out std_logic;
    Mx_Ready : in  std_logic;
    Mx_PC    : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    Mx_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end FunctionDMUX;

library ieee;
use ieee.numeric_std.all;
architecture arch of FunctionDMUX is
  signal M0_selected: std_logic;
  signal M1_selected: std_logic;
  signal Mx_selected: std_logic;
begin

  M0_Valid <= S_Valid when M0_selected='1' else '0';
  M0_PC    <= S_PC;
  M0_ThNo  <= S_ThNo;
  M0_Imm12 <= S_Imm12;
  M0_rs1V  <= S_rs1V;
  M0_rs2V  <= S_rs2V;
  M0_rd    <= S_rd;
  M0_cmd   <= S_cmd;
  
  M1_Valid <= S_Valid when M1_selected='1' else '0';
  M1_PC    <= S_PC;
  M1_ThNo  <= S_ThNo;
  M1_Imm12 <= S_Imm12;
  M1_rs1V  <= S_rs1V;
  M1_rs2V  <= S_rs2V;
  M1_rd    <= S_rd;
  M1_cmd   <= S_cmd;

  Mx_Valid <= S_Valid when Mx_selected='1' else '0';
  Mx_PC    <= S_PC;
  Mx_ThNo  <= S_ThNo;

  S_Ready <= M0_Ready when M0_selected='1' else
             M1_Ready when M1_selected='1' else
             Mx_Ready when Mx_selected='1' else
             '0';

  process (S_cmd)
  begin
    M0_selected <= '0';
    M1_selected <= '0';
    Mx_selected <= '0';
    if    S_cmd="0"&"000"&"1100111" then M0_selected <= '1'; --JALR
    elsif S_cmd="0"&"000"&"1100011" then M0_selected <= '1'; --BEQ
    elsif S_cmd="0"&"001"&"1100011" then M0_selected <= '1'; --BNE
    elsif S_cmd="0"&"100"&"1100011" then M0_selected <= '1'; --BLT
    elsif S_cmd="0"&"101"&"1100011" then M0_selected <= '1'; --BGE
    elsif S_cmd="0"&"110"&"1100011" then M0_selected <= '1'; --BLTU
    elsif S_cmd="0"&"111"&"1100011" then M0_selected <= '1'; --BGEU
    elsif S_cmd="0"&"000"&"0010011" then M0_selected <= '1'; --ADDI 
    elsif S_cmd="0"&"010"&"0010011" then M0_selected <= '1'; --SLTI 
    elsif S_cmd="0"&"011"&"0010011" then M0_selected <= '1'; --SLTIU
    elsif S_cmd="0"&"100"&"0010011" then M0_selected <= '1'; --XORI 
    elsif S_cmd="0"&"110"&"0010011" then M0_selected <= '1'; --ORI  
    elsif S_cmd="0"&"111"&"0010011" then M0_selected <= '1'; --ANDI 
    elsif S_cmd="0"&"001"&"0010011" then M0_selected <= '1'; --SLLI 
    elsif S_cmd="0"&"101"&"0010011" then M0_selected <= '1'; --SRLI 
    elsif S_cmd="1"&"101"&"0010011" then M0_selected <= '1'; --SRAI 
    elsif S_cmd="0"&"000"&"0110011" then M0_selected <= '1'; --ADD  
    elsif S_cmd="1"&"000"&"0110011" then M0_selected <= '1'; --SUB  
    elsif S_cmd="0"&"001"&"0110011" then M0_selected <= '1'; --SLL  
    elsif S_cmd="0"&"010"&"0110011" then M0_selected <= '1'; --SLT  
    elsif S_cmd="0"&"011"&"0110011" then M0_selected <= '1'; --SLTU 
    elsif S_cmd="0"&"100"&"0110011" then M0_selected <= '1'; --XOR  
    elsif S_cmd="0"&"101"&"0110011" then M0_selected <= '1'; --SRL  
    elsif S_cmd="1"&"101"&"0110011" then M0_selected <= '1'; --SRA  
    elsif S_cmd="0"&"110"&"0110011" then M0_selected <= '1'; --OR   
    elsif S_cmd="0"&"111"&"0110011" then M0_selected <= '1'; --AND  
     --              
    elsif S_cmd="0"&"000"&"0000011" then M1_selected <= '1'; --LB   
    elsif S_cmd="0"&"001"&"0000011" then M1_selected <= '1'; --LH   
    elsif S_cmd="0"&"010"&"0000011" then M1_selected <= '1'; --LW   
    elsif S_cmd="0"&"100"&"0000011" then M1_selected <= '1'; --LBU  
    elsif S_cmd="0"&"101"&"0000011" then M1_selected <= '1'; --LHU  
    elsif S_cmd="0"&"000"&"0100011" then M1_selected <= '1'; --SB   
    elsif S_cmd="0"&"001"&"0100011" then M1_selected <= '1'; --SH   
    elsif S_cmd="0"&"010"&"0100011" then M1_selected <= '1'; --SW
    --
    else                                 Mx_selected <= '1';
    end if ;
  end process;


end arch;
