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
-- InstructionDMUX
-- This pipeline stage routes the instructions to their respective processing blocks 
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity InstructionDMUX is
  generic (
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    -- Input
    S_Valid  : in  std_logic;
    S_Ready  : out std_logic;
    S_PC     : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_Inst   : in  std_logic_vector(31 downto 0);
    -- Output for instructions lui, auipc, jal
    M0_Valid : out std_logic;
    M0_Ready : in  std_logic;
    M0_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M0_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M0_Inst  : out std_logic_vector(31 downto 0);
    -- Output for other supported instructions
    M1_Valid : out std_logic;
    M1_Ready : in  std_logic;
    M1_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M1_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M1_Imm12 : out std_logic_vector(11 downto 0);
    M1_rs1   : out std_logic_vector( 4 downto 0);
    M1_rs2   : out std_logic_vector( 4 downto 0);
    M1_rd    : out std_logic_vector( 4 downto 0);
    M1_cmd   : out std_logic_vector(10 downto 0);
    -- Output for wfi instruction
    M2_Valid : out std_logic;
    M2_Ready : in  std_logic;
    M2_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M2_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output for ebreak instruction
    M3_Valid : out std_logic;
    M3_Ready : in  std_logic;
    M3_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M3_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output for not supported instructions
    Mx_Valid : out std_logic;
    Mx_Ready : in  std_logic;
    Mx_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    Mx_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end InstructionDMUX;

library ieee;
use ieee.numeric_std.all;
architecture arch of InstructionDMUX is
  signal M0_selected : std_logic;
  signal M1_selected : std_logic;
  signal M2_selected : std_logic;
  signal M3_selected : std_logic;
  signal Mx_selected : std_logic;
  function cmp_inst(
    inst: std_logic_vector(31 downto 0);
    code: std_logic_vector(31 downto 0)
  ) return boolean is
    variable result : boolean := true;
  begin
    for i in inst'range loop
      if code(i) /= '-' then
        if code(i) /= inst(i) then
          result := false;
          exit;
        end if;
      end if;
    end loop;
    return result;
  end function;  
begin

  -- Forward instruction to suitable output
  M0_Valid <= S_Valid when M0_selected='1' else '0';
  M1_Valid <= S_Valid when M1_selected='1' else '0';
  M2_Valid <= S_Valid when M2_selected='1' else '0';
  M3_Valid <= S_Valid when M3_selected='1' else '0';
  Mx_Valid <= S_Valid when Mx_selected='1' else '0';
  
  -- Get ready from selected output
  S_Ready <= M0_Ready when M0_selected='1' else
             M1_Ready when M1_selected='1' else
             M2_Ready when M2_selected='1' else
             M3_Ready when M3_selected='1' else
             Mx_Ready when Mx_selected='1' else
             'X';
  
  -- forward instruction information to the DMUX outputs
  M0_PC <= S_PC; M0_ThNo     <= S_ThNo; M0_Inst <= S_Inst;
  M1_PC <= S_PC; M1_ThNo     <= S_ThNo;
  M2_PC <= S_PC; M2_ThNo     <= S_ThNo;
  M3_PC <= std_logic_vector(unsigned(S_PC)-4); M3_ThNo <= S_ThNo;
  Mx_PC <= S_PC; Mx_ThNo <= S_ThNo;

  -- do DEMUXing and more
  process(S_Inst)
  begin
    M0_selected <= '0'; 
    M1_selected <= '0'; 
    M2_selected <= '0'; 
    M3_selected <= '0'; 
    Mx_selected <= '0';
    M1_Imm12 <= (M1_Imm12'range =>'0'); 
    M1_rs1   <= (M1_rs1'range =>'0'); 
    M1_rs2   <= (M1_rs2'range =>'0'); 
    M1_rd    <= (M1_rd'range =>'0'); 
    M1_cmd   <= (M1_cmd'range =>'0'); 
    --                  imm    rs2  rs1  fkt rd  opcode
    --                  |-----||---||---||-||---||-----|
    if    cmp_inst(S_Inst,"-------------------------0110111") then M0_selected <= '1'; -- LUI
    elsif cmp_inst(S_Inst,"-------------------------0010111") then M0_selected <= '1'; -- AUIPC
    elsif cmp_inst(S_Inst,"-------------------------1101111") then
      M0_selected  <= '1'; -- JAL
    ---
    elsif cmp_inst(S_Inst,"-----------------000-----1100111") -- JALR
       or cmp_inst(S_Inst,"-----------------000-----0000011") -- LB
       or cmp_inst(S_Inst,"-----------------001-----0000011") -- LH
       or cmp_inst(S_Inst,"-----------------010-----0000011") -- LW
       or cmp_inst(S_Inst,"-----------------100-----0000011") -- LBU
       or cmp_inst(S_Inst,"-----------------101-----0000011") -- LHU
       or cmp_inst(S_Inst,"-----------------000-----0010011") -- ADDI
       or cmp_inst(S_Inst,"-----------------010-----0010011") -- SLTI
       or cmp_inst(S_Inst,"-----------------011-----0010011") -- SLTIU
       or cmp_inst(S_Inst,"-----------------100-----0010011") -- XORI
       or cmp_inst(S_Inst,"-----------------110-----0010011") -- ORI
       or cmp_inst(S_Inst,"-----------------111-----0010011") -- ANDI
    then
      M1_selected <= '1';
      M1_Imm12    <= S_Inst(31 downto 20);
      M1_rs1      <= S_Inst(19 downto 15);
      M1_rs2      <= "00000";
      M1_rd       <= S_Inst(11 downto 7);
      M1_cmd      <= "0" & S_Inst(14 downto 12) & S_Inst(6 downto 0);
    elsif cmp_inst(S_Inst,"-----------------000-----1100011") -- BEQ
       or cmp_inst(S_Inst,"-----------------001-----1100011") -- BNE
       or cmp_inst(S_Inst,"-----------------100-----1100011") -- BLT
       or cmp_inst(S_Inst,"-----------------101-----1100011") -- BGE
       or cmp_inst(S_Inst,"-----------------110-----1100011") -- BLTU
       or cmp_inst(S_Inst,"-----------------111-----1100011") -- BGEU
    then
      M1_selected <= '1';
      M1_Imm12    <= S_Inst(31) & S_Inst(7) & S_Inst(30 downto 25) & S_Inst(11 downto 8);
      M1_rs1      <= S_Inst(19 downto 15);
      M1_rs2      <= S_Inst(24 downto 20);
      M1_rd       <= "00000";
      M1_cmd      <= "0" & S_Inst(14 downto 12) & S_Inst(6 downto 0);
    elsif cmp_inst(S_Inst,"-----------------000-----0100011") -- SB
       or cmp_inst(S_Inst,"-----------------001-----0100011") -- SH
       or cmp_inst(S_Inst,"-----------------010-----0100011") -- SW
    then
      M1_selected <= '1';
      M1_Imm12    <= S_Inst(31 downto 25) & S_Inst(11 downto 7);
      M1_rs1      <= S_Inst(19 downto 15);
      M1_rs2      <= S_Inst(24 downto 20);
      M1_rd       <= "00000";
      M1_cmd      <= "0" & S_Inst(14 downto 12) & S_Inst(6 downto 0);
    elsif cmp_inst(S_Inst,"0000000----------001-----0010011") -- SLLI
       or cmp_inst(S_Inst,"0000000----------101-----0010011") -- SRLI
       or cmp_inst(S_Inst,"0100000----------101-----0010011") -- SRAI
    then
      M1_selected <= '1';
      M1_Imm12    <= "0000000" & S_Inst(24 downto 20);
      M1_rs1      <= S_Inst(19 downto 15);
      M1_rs2      <= "00000";
      M1_rd       <= S_Inst(11 downto 7);
      M1_cmd      <= S_Inst(30) & S_Inst(14 downto 12) & S_Inst(6 downto 0);
    elsif cmp_inst(S_Inst,"0000000----------000-----0110011") -- ADD
       or cmp_inst(S_Inst,"0100000----------000-----0110011") -- SUB
       or cmp_inst(S_Inst,"0000000----------001-----0110011") -- SLL
       or cmp_inst(S_Inst,"0000000----------010-----0110011") -- SLT
       or cmp_inst(S_Inst,"0000000----------011-----0110011") -- SLTU
       or cmp_inst(S_Inst,"0000000----------100-----0110011") -- XOR
       or cmp_inst(S_Inst,"0000000----------101-----0110011") -- SRL
       or cmp_inst(S_Inst,"0100000----------101-----0110011") -- SRA
       or cmp_inst(S_Inst,"0000000----------110-----0110011") -- OR
       or cmp_inst(S_Inst,"0000000----------111-----0110011") -- AND
    then
      M1_selected <= '1';
      M1_Imm12    <= "000000000000";
      M1_rs1      <= S_Inst(19 downto 15);
      M1_rs2      <= S_Inst(24 downto 20);
      M1_rd       <= S_Inst(11 downto 7);
      M1_cmd      <= S_Inst(30) & S_Inst(14 downto 12) & S_Inst(6 downto 0);
    elsif cmp_inst(S_Inst,"00010000010100000000000001110011") then M2_selected <= '1'; -- WFI
    elsif cmp_inst(S_Inst,"00000000000100000000000001110011") then M3_selected <= '1'; -- EBREAK
 -- elsif cmp_inst(S_Inst,"-----------------000-----0001111") then Mx_selected <= '1'; -- FENCE
 -- elsif cmp_inst(S_Inst,"00000000000000000000000001110011") then Mx_selected <= '1'; -- ECALL
 -- elsif cmp_inst(S_Inst,"-----------------001-----0001111") then Mx_selected <= '1'; -- FENCE.I
 -- elsif cmp_inst(S_Inst,"-----------------001-----1110011") then Mx_selected <= '1'; -- CSRRW
 -- elsif cmp_inst(S_Inst,"-----------------010-----1110011") then Mx_selected <= '1'; -- CSRRS
 -- elsif cmp_inst(S_Inst,"-----------------011-----1110011") then Mx_selected <= '1'; -- CSRRC
 -- elsif cmp_inst(S_Inst,"-----------------101-----1110011") then Mx_selected <= '1'; -- CSRRWI
 -- elsif cmp_inst(S_Inst,"-----------------110-----1110011") then Mx_selected <= '1'; -- CSRRSI
 -- elsif cmp_inst(S_Inst,"-----------------111-----1110011") then Mx_selected <= '1'; -- CSRRCI
 -- elsif cmp_inst(S_Inst,"0000001----------000-----0110011") then Mx_selected <= '1'; -- MUL
 -- elsif cmp_inst(S_Inst,"0000001----------001-----0110011") then Mx_selected <= '1'; -- MULH
 -- elsif cmp_inst(S_Inst,"0000001----------010-----0110011") then Mx_selected <= '1'; -- MULHSU
 -- elsif cmp_inst(S_Inst,"0000001----------011-----0110011") then Mx_selected <= '1'; -- MULHU
 -- elsif cmp_inst(S_Inst,"0000001----------100-----0110011") then Mx_selected <= '1'; -- DIV
 -- elsif cmp_inst(S_Inst,"0000001----------101-----0110011") then Mx_selected <= '1'; -- DIVU
 -- elsif cmp_inst(S_Inst,"0000001----------110-----0110011") then Mx_selected <= '1'; -- REM
 -- elsif cmp_inst(S_Inst,"0000001----------111-----0110011") then Mx_selected <= '1'; -- REMU
    ---
    else                                                           Mx_selected <= '1';
    end if;
  end process;
  
end arch; -- InstructionDMUX