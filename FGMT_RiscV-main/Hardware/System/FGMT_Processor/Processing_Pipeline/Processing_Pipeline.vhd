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
-- Processing_Pipeline
-- The processing pipeline is the central component of the FGMT processor where the
-- computing takes place. It is organized as an axi streaming pipeline.
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
--use work.FGMT_pack.all;
entity Processing_Pipeline is
  generic (
    ADR_WIDTH       : integer := 13; -- Values in range 32..13
    THREAD_NO_WIDTH : integer :=  3;
    ERR_ID_WIDTH    : integer :=  2
  );
  port (
    CLK          : in  std_logic;
    RESET        : in  std_logic;
    -- Input
    S_Valid      : in  std_logic;
    S_Ready      : out std_logic;
    S_PC         : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo       : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- IBUS: Stream to Instruction Memory: Address Stream
    MI_Valid     : out std_logic;
    MI_Ready     : in  std_logic;
    MI_ADR       : out std_logic_vector(ADR_WIDTH-1 downto 1);
    MI_ThNo      : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- IBUS: Stream from Instruction Memory: Data Stream
    SI_Valid     : in  std_logic;
    SI_Ready     : out std_logic;
    SI_Inst      : in  std_logic_vector(31 downto 0);
    -- DBUS: Data Memory Write stream
    MW_Valid     : out std_logic;
    MW_Ready     : in  std_logic;
    MW_ADR       : out std_logic_vector(ADR_WIDTH-1 downto 2);
    MW_ThNo      : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    MW_DAT       : out std_logic_vector(31 downto 0);
    MW_SEL       : out std_logic_vector(3 downto 0);
    -- DBUS: Data Memory Read Address stream
    MR_Valid     : out std_logic;
    MR_Ready     : in  std_logic;
    MR_ADR       : out std_logic_vector(ADR_WIDTH-1 downto 2);
    MR_ThNo      : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- DBUS: Data Memory Read Response stream
    SR_Valid     : in  std_logic;
    SR_Ready     : out std_logic;
    SR_DAT       : in  std_logic_vector(31 downto 0);
    -- Output
    M_Valid      : out std_logic;
    M_Ready      : in  std_logic;
    M_PC         : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo       : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output to Interrupt Controller (IRC)
    Wfi_Valid    : out std_logic;
    Wfi_Ready    : in  std_logic;
    Wfi_PC       : out std_logic_vector(ADR_WIDTH-1 downto 0);
    Wfi_ThNo     : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Output for ebreak commands
    EBK_Valid    : out std_logic;
    EBK_Ready    : in  std_logic;
    EBK_PC       : out std_logic_vector(ADR_WIDTH-1 downto 0);
    EBK_ThNo     : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Error Output
    Mx_Valid     : out std_logic;
    Mx_Ready     : in  std_logic;
    Mx_PC        : out std_logic_vector(ADR_WIDTH-1 downto 0);
    Mx_ThNo      : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    Mx_ErrID     : out std_logic_vector(ERR_ID_WIDTH-1 downto 0);
    -- Injection signals
    IJ_Active    : in  std_logic;
    IJ_ThNo      : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    IJ_Inst      : in  std_logic_vector(31 downto 0);
    IJ_RegV      : out std_logic_vector(31 downto 0);
    --
    AxsVect      : out std_logic_vector(31 downto 0)
  );
end Processing_Pipeline;

library ieee;
use ieee.numeric_std.all;
architecture arch of Processing_Pipeline is
  constant NoSync    : integer := 0;
  constant DataSync  : integer := 1;
  constant ReadySync : integer := 2;
  constant RandDSync : integer := 3;
  -- Interface to Register Memory, Read Port
  signal R2M_Valid        : std_logic;
  signal R2M_Ready        : std_logic;
  signal R2M_ADR1         : std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
  signal R2M_ADR2         : std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
  signal R2M_Sel1         : std_logic;
  signal R2M_Sel2         : std_logic;
  signal M2R_Valid        : std_logic;
  signal M2R_Ready        : std_logic;
  signal M2R_rs1V         : std_logic_vector(31 downto 0);
  signal M2R_rs2V         : std_logic_vector(31 downto 0);  
  -- Interface to Register Memory, Write Port
  signal W2M_Valid        : std_logic;
  signal W2M_Ready        : std_logic;
  signal W2M_ADR          : std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
  signal W2M_rdV          : std_logic_vector(31 downto 0);
  -- from ReadOpcode_and_IncPC to InstructionDMUX
  signal Inst_Valid       : std_logic := '0';
  signal Inst_Ready       : std_logic := '0';
  signal Inst_PC          : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Inst_ThNo        : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Inst_Inst        : std_logic_vector(31 downto 0);
  -- Error Bus for Instruction Read Alignment Error
  signal InstErr_Valid    : std_logic := '0';
  signal InstErr_Ready    : std_logic := '0';
  signal InstErr_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal InstErr_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- from InstructionDMUX to Set_PC_and_rd
  signal Set_Valid        : std_logic := '0';
  signal Set_Ready        : std_logic := '0';
  signal Set_PC           : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Set_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Set_Inst         : std_logic_vector(31 downto 0);
  -- from InstructionDMUX to Read_Source_Registers
  signal Read_Valid       : std_logic := '0';
  signal Read_Ready       : std_logic := '0';
  signal Read_PC          : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Read_ThNo        : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Read_Imm12       : std_logic_vector(11 downto 0);
  signal Read_rs1         : std_logic_vector( 4 downto 0);
  signal Read_rs2         : std_logic_vector( 4 downto 0);
  signal Read_rd          : std_logic_vector( 4 downto 0);
  signal Read_cmd         : std_logic_vector(10 downto 0);
  -- IDMUX Error Output for not supported instructions
  signal IDErr_Valid      : std_logic := '0';
  signal IDErr_Ready      : std_logic := '0';
  signal IDErr_PC         : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal IDErr_ThNo       : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- from Read_Source_Registers to FunctionDMUX
  signal Func_Valid       : std_logic := '0';
  signal Func_Ready       : std_logic := '0';
  signal Func_PC          : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Func_ThNo        : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Func_Imm12       : std_logic_vector(11 downto 0);
  signal Func_rs1V        : std_logic_vector(31 downto 0);
  signal Func_rs2V        : std_logic_vector(31 downto 0);
  signal Func_rd          : std_logic_vector( 4 downto 0);
  signal Func_cmd         : std_logic_vector(10 downto 0);
  -- from FunctionDMUX to Register_Commands
  signal Reg_Valid        : std_logic := '0';
  signal Reg_Ready        : std_logic := '0';
  signal Reg_PC           : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Reg_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Reg_Imm12        : std_logic_vector(11 downto 0);
  signal Reg_rs1V         : std_logic_vector(31 downto 0);
  signal Reg_rs2V         : std_logic_vector(31 downto 0);
  signal Reg_rd           : std_logic_vector( 4 downto 0);
  signal Reg_cmd          : std_logic_vector(10 downto 0);
  -- from FunctionDMUX to Data_Memory_LoadStore
  signal Mem_Valid        : std_logic := '0';
  signal Mem_Ready        : std_logic := '0';
  signal Mem_PC           : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Mem_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Mem_Imm12        : std_logic_vector(11 downto 0);
  signal Mem_rs1V         : std_logic_vector(31 downto 0);
  signal Mem_rs2V         : std_logic_vector(31 downto 0);
  signal Mem_rd           : std_logic_vector( 4 downto 0);
  signal Mem_cmd          : std_logic_vector(10 downto 0);
  -- from Set_PC_and_rd to StoreResultMUX
  signal SR2_Valid        : std_logic := '0';
  signal SR2_Ready        : std_logic := '0';
  signal SR2_PC           : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal SR2_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal SR2_rdV          : std_logic_vector(31 downto 0);
  signal SR2_rd           : std_logic_vector( 4 downto 0);
  -- from Register_Commands to StoreResultMUX
  signal SR1_Valid        : std_logic := '0';
  signal SR1_Ready        : std_logic := '0';
  signal SR1_PC           : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal SR1_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal SR1_rdV          : std_logic_vector(31 downto 0);
  signal SR1_rd           : std_logic_vector( 4 downto 0);
  -- from DataMem_LoadStore to StoreResultMUX
  signal SR0_Valid        : std_logic := '0';
  signal SR0_Ready        : std_logic := '0';
  signal SR0_PC           : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal SR0_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal SR0_rdV          : std_logic_vector(31 downto 0);
  signal SR0_rd           : std_logic_vector( 4 downto 0);
  -- Error Output of DataMem_LoadStore
  signal DMLSErr_Valid    : std_logic := '0';
  signal DMLSErr_Ready    : std_logic := '0';
  signal DMLSErr_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal DMLSErr_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- from StoreResultMUX to Write_Result_to_Register
  signal WRR_Valid    : std_logic := '0';
  signal WRR_Ready    : std_logic := '0';
  signal WRR_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal WRR_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal WRR_rdV      : std_logic_vector(31 downto 0);
  signal WRR_rd       : std_logic_vector( 4 downto 0);
  --
  signal S_iReady     : std_logic;
  signal M_iValid     : std_logic;
  signal EBK_iValid   : std_logic;
  signal Wfi_iValid   : std_logic;
  signal Mx_iValid    : std_logic;
  signal MI_iValid    : std_logic;
  signal SI_iReady    : std_logic;
  signal MW_iValid    : std_logic;
  signal MR_iValid    : std_logic;
  signal SR_iReady    : std_logic;
begin
 
  S_Ready   <= S_iReady;
  M_Valid   <= M_iValid;
  EBK_Valid <= EBK_iValid;
  Wfi_Valid <= Wfi_iValid;
  Mx_Valid  <= Mx_iValid;
  --
  MI_Valid <= MI_iValid;
  SI_Ready <= SI_iReady;
  --
  MW_Valid <= MW_iValid;
  MR_Valid <= MR_iValid;
  SR_Ready <= SR_iReady;

  -- Measure 2
  AxsVect( 1 downto  0) <= S_Valid    & S_iReady;
  AxsVect( 3 downto  2) <= MI_iValid  & MI_Ready;
  AxsVect( 5 downto  4) <= SI_Valid   & SI_iReady;
  AxsVect( 7 downto  6) <= Inst_Valid & Inst_Ready;
  AxsVect( 9 downto  8) <= Read_Valid & Read_Ready;
  AxsVect(11 downto 10) <= Func_Valid & Func_Ready;
  AxsVect(13 downto 12) <= Mem_Valid  & Mem_Ready;
  AxsVect(15 downto 14) <= MR_iValid  & MR_Ready;
  AxsVect(17 downto 16) <= SR_Valid   & SR_iReady;
  AxsVect(19 downto 18) <= MW_iValid  & MW_Ready;
  AxsVect(21 downto 20) <= SR0_Valid  & SR0_Ready;
  AxsVect(23 downto 22) <= WRR_Valid  & WRR_Ready;
  AxsVect(25 downto 24) <= M_iValid   & M_Ready;
  AxsVect(31 downto 26) <= (others=>'0');

  ROaIBlock: block
    signal tmp_Valid    : std_logic := '0';
    signal tmp_Ready    : std_logic := '0';
    signal tmp_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal tmp_Inst     : std_logic_vector(31 downto 0);
    constant Inst_Base  : integer := 0;
    constant ThNo_Base  : integer := Inst_Base + tmp_Inst'LENGTH;
    constant PC_Base    : integer := ThNo_Base + tmp_ThNo'LENGTH;
    constant DATA_WIDTH : integer := PC_Base   + tmp_PC'LENGTH;
    signal tmp_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal Inst_Data    : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
  
    ROaI: entity work.ReadOpcode_and_IncPC
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
        CLK         => CLK,
        RESET       => RESET,
        -- Input
        S_Valid     => S_Valid,
        S_Ready     => S_iReady,
        S_PC        => S_PC,
        S_ThNo      => S_ThNo,
        -- Generate Address Stream
        MI_Valid    => MI_iValid,
        MI_Ready    => MI_Ready,
        MI_ADR      => MI_ADR,
        MI_ThNo     => MI_ThNo,
        -- Read Data Stream
        SI_Valid    => SI_Valid,
        SI_Ready    => SI_iReady,
        SI_Inst     => SI_Inst,
        -- Output with Valid Instruction
        M_Valid     => tmp_Valid,
        M_Ready     => tmp_Ready,
        M_PC        => tmp_PC,
        M_ThNo      => tmp_ThNo,
        M_Inst      => tmp_Inst,
        -- Output on Alignment Error
        Mx_Valid    => InstErr_Valid,
        Mx_Ready    => InstErr_Ready,
        Mx_PC       => InstErr_PC,
        Mx_ThNo     => InstErr_ThNo,
        -- Injection Inputs
        IJ_Active   => IJ_Active,
        IJ_ThNo     => IJ_ThNo,
        IJ_Inst     => IJ_Inst
      );
    --
    tmp_Data <= tmp_PC & tmp_ThNo & tmp_Inst;
    OBUFF: entity work.OutputBuffering
      generic map (
        SyncOnOutput => RandDSync,
        DATA_WIDTH   => DATA_WIDTH
      )
      port map (
        CLK     => CLK,
        RESET   => RESET,
        -- Input
        S_Valid => tmp_Valid,
        S_Ready => tmp_Ready,
        S_Data  => tmp_Data,
        -- Output
        M_Valid => Inst_Valid,
        M_Ready => Inst_Ready,
        M_Data  => Inst_Data
      );
    Inst_PC   <= Inst_Data(  tmp_PC'LENGTH+PC_Base-1   downto PC_Base);      
    Inst_ThNo <= Inst_Data(tmp_ThNo'LENGTH+ThNo_Base-1 downto ThNo_Base);
    Inst_Inst <= Inst_Data(tmp_Inst'LENGTH+Inst_Base-1 downto Inst_Base); -- x"0000006f"; -- endless loop
  end block;

  IDUX: entity work.InstructionDMUX
    generic  map (
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      --RESET     => RESET;
      -- Input
      S_Valid     => Inst_Valid,
      S_Ready     => Inst_Ready,
      S_PC        => Inst_PC,
      S_ThNo      => Inst_ThNo,
      S_Inst      => Inst_Inst,
      -- Output for instructions lui, auipc, jal
      M0_Valid    => Set_Valid,
      M0_Ready    => Set_Ready,
      M0_PC       => Set_PC,
      M0_ThNo     => Set_ThNo,
      M0_Inst     => Set_Inst,
      -- Output for other supported instructions
      M1_Valid    => Read_Valid,
      M1_Ready    => Read_Ready,
      M1_PC       => Read_PC,
      M1_ThNo     => Read_ThNo,
      M1_Imm12    => Read_Imm12,
      M1_rs1      => Read_rs1,
      M1_rs2      => Read_rs2,
      M1_rd       => Read_rd,
      M1_cmd      => Read_cmd,
      -- Output for wfi instruction
      M2_Valid    => Wfi_iValid,
      M2_Ready    => Wfi_Ready,
      M2_PC       => Wfi_PC,
      M2_ThNo     => Wfi_ThNo,
      -- Output for ebreak instruction
      M3_Valid    => EBK_iValid,
      M3_Ready    => EBK_Ready,
      M3_PC       => EBK_PC,
      M3_ThNo     => EBK_ThNo,
      -- Output for not supported instructions
      Mx_Valid    => IDErr_Valid,
      Mx_Ready    => IDErr_Ready,
      Mx_PC       => IDErr_PC,
      Mx_ThNo     => IDErr_ThNo
    );

  RSRBlock: block
    signal tmp_Valid    : std_logic := '0';
    signal tmp_Ready    : std_logic := '0';
    signal tmp_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal tmp_Imm12    : std_logic_vector(11 downto 0);
    signal tmp_rs1V     : std_logic_vector(31 downto 0);
    signal tmp_rs2V     : std_logic_vector(31 downto 0);
    signal tmp_rd       : std_logic_vector( 4 downto 0);
    signal tmp_cmd      : std_logic_vector(10 downto 0);
    constant cmd_Base   : integer := 0;
    constant rd_Base    : integer := cmd_Base   + tmp_cmd'LENGTH;
    constant rs2V_Base  : integer := rd_Base    + tmp_rd'LENGTH;
    constant rs1V_Base  : integer := rs2V_Base  + tmp_rs2V'LENGTH;
    constant Imm12_Base : integer := rs1V_Base  + tmp_rs1V'LENGTH;
    constant ThNo_Base  : integer := Imm12_Base + tmp_Imm12'LENGTH;
    constant PC_Base    : integer := ThNo_Base  + tmp_ThNo'LENGTH;
    constant DATA_WIDTH : integer := PC_Base    + tmp_PC'LENGTH;
    signal tmp_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal Func_Data    : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    RSR: entity work.ReadRegisters
      generic map (
        INST_ADDR_WIDTH => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
        CLK      => CLK,
        RESET    => RESET,
        -- Input from Instruction DMUX
        S_Valid  => Read_Valid,
        S_Ready  => Read_Ready,
        S_PC     => Read_PC,
        S_ThNo   => Read_ThNo,
        S_Imm12  => Read_Imm12,
        S_rs1    => Read_rs1,
        S_rs2    => Read_rs2,
        S_rd     => Read_rd,
        S_cmd    => Read_cmd,
        -- Stream to register read
        MR_Valid => R2M_Valid,
        MR_Ready => R2M_Ready,
        MR_ADR1  => R2M_ADR1,
        MR_ADR2  => R2M_ADR2,
        MR_Sel1  => R2M_Sel1,
        MR_Sel2  => R2M_Sel2,
        -- Stream from register read
        SR_Valid => M2R_Valid,
        SR_Ready => M2R_Ready,
        SR_rs1V  => M2R_rs1V,
        SR_rs2V  => M2R_rs2V,
        -- Output to Function DMUX
        M_Valid  => tmp_Valid,
        M_Ready  => tmp_Ready,
        M_PC     => tmp_PC,
        M_ThNo   => tmp_ThNo,
        M_Imm12  => tmp_Imm12,
        M_rs1V   => tmp_rs1V,
        M_rs2V   => tmp_rs2V,
        M_rd     => tmp_rd,
        M_cmd    => tmp_cmd
      );
    --       
    tmp_Data <= tmp_PC & tmp_ThNo & tmp_Imm12 & tmp_rs1V & tmp_rs2V & tmp_rd & tmp_cmd;
    OBUFF: entity work.OutputBuffering
      generic map (
        SyncOnOutput => RandDSync,
        DATA_WIDTH   => DATA_WIDTH
      )
      port map (
        CLK     => CLK,
        RESET   => RESET,
        -- Input
        S_Valid => tmp_Valid,
        S_Ready => tmp_Ready,
        S_Data  => tmp_Data,
        -- Output
        M_Valid => Func_Valid,
        M_Ready => Func_Ready,
        M_Data  => Func_Data
      );
    Func_PC    <= Func_Data(   tmp_PC'LENGTH+PC_Base-1    downto PC_Base);
    Func_ThNo  <= Func_Data( tmp_ThNo'LENGTH+ThNo_Base-1  downto ThNo_Base);
    Func_Imm12 <= Func_Data(tmp_Imm12'LENGTH+Imm12_Base-1 downto Imm12_Base);
    Func_rs1V  <= Func_Data( tmp_rs1V'LENGTH+rs1V_Base-1  downto rs1V_Base);
    Func_rs2V  <= Func_Data( tmp_rs2V'LENGTH+rs2V_Base-1  downto rs2V_Base);
    Func_rd    <= Func_Data(   tmp_rd'LENGTH+rd_Base-1    downto rd_Base);
    Func_cmd   <= Func_Data(  tmp_cmd'LENGTH+cmd_Base-1   downto cmd_Base);
  end block;

  FDMUX: entity work.FunctionDMUX
    generic map (
      INST_ADDR_WIDTH => ADR_WIDTH,
      DATA_ADDR_WIDTH => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      -- Input
      S_Valid  => Func_Valid,
      S_Ready  => Func_Ready,
      S_PC     => Func_PC,
      S_ThNo   => Func_ThNo,
      S_Imm12  => Func_Imm12,
      S_rs1V   => Func_rs1V,
      S_rs2V   => Func_rs2V,
      S_rd     => Func_rd,
      S_cmd    => Func_cmd,
      -- Output for Register Commands
      M0_Valid => Reg_Valid,
      M0_Ready => Reg_Ready,
      M0_PC    => Reg_PC,
      M0_ThNo  => Reg_ThNo,
      M0_Imm12 => Reg_Imm12,
      M0_rs1V  => Reg_rs1V,
      M0_rs2V  => Reg_rs2V,
      M0_rd    => Reg_rd,
      M0_cmd   => Reg_cmd,
      -- Output for Data Memory Load/Store
      M1_Valid => Mem_Valid,
      M1_Ready => Mem_Ready,
      M1_PC    => Mem_PC,
      M1_ThNo  => Mem_ThNo,
      M1_Imm12 => Mem_Imm12,
      M1_rs1V  => Mem_rs1V,
      M1_rs2V  => Mem_rs2V,
      M1_rd    => Mem_rd,
      M1_cmd   => Mem_cmd,
      -- Let FunctionDMUX hang in case of malfunctions
      Mx_Valid => open,
      Mx_Ready => '0',
      Mx_PC    => open,
      Mx_ThNo  => open
    );

  SpCmdsBlock: block
    signal tmp_Valid    : std_logic :='0';
    signal tmp_Ready    : std_logic :='0';
    signal tmp_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal tmp_rdV      : std_logic_vector(31 downto 0);
    signal tmp_rd       : std_logic_vector( 4 downto 0);
    constant rd_Base    : integer := 0;
    constant rdV_Base   : integer := rd_Base   + tmp_rd'LENGTH;
    constant ThNo_Base  : integer := rdV_Base  + tmp_rdV'LENGTH;
    constant PC_Base    : integer := ThNo_Base + tmp_ThNo'LENGTH;
    constant DATA_WIDTH : integer := PC_Base   + tmp_PC'LENGTH;
    signal tmp_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal SR2_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    SpCmds: entity work.SpecialCmds
      generic map (
        INST_ADDR_WIDTH => ADR_WIDTH,
        DATA_ADDR_WIDTH => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
        --RESET       => RESET;
        -- Input
        S_Valid => Set_Valid,
        S_Ready => Set_Ready,
        S_PC    => Set_PC,
        S_ThNo  => Set_ThNo,
        S_Inst  => Set_Inst,
        -- Output for instructions lui, auipc, jal
        M_Valid => tmp_Valid,
        M_Ready => tmp_Ready,
        M_PC    => tmp_PC,
        M_ThNo  => tmp_ThNo,
        M_rdV   => tmp_rdV,
        M_rd    => tmp_rd
      );
    --
    tmp_Data <= tmp_PC & tmp_ThNo & tmp_rdV & tmp_rd;
    OBUFF: entity work.OutputBuffering
      generic map (
        SyncOnOutput => RandDSync,
        DATA_WIDTH   => DATA_WIDTH
      )
      port map (
        CLK     => CLK,
        RESET   => RESET,
        -- Input
        S_Valid => tmp_Valid,
        S_Ready => tmp_Ready,
        S_Data  => tmp_Data,
        -- Output
        M_Valid => SR2_Valid,
        M_Ready => SR2_Ready,
        M_Data  => SR2_Data
      );
    SR2_PC   <= SR2_Data(  tmp_PC'LENGTH+PC_Base-1   downto PC_Base);
    SR2_ThNo <= SR2_Data(tmp_ThNo'LENGTH+ThNo_Base-1 downto ThNo_Base);
    SR2_rdV  <= SR2_Data( tmp_rdV'LENGTH+rdV_Base-1  downto rdV_Base);
    SR2_rd   <= SR2_Data(  tmp_rd'LENGTH+rd_Base-1   downto rd_Base);
  end block;

  PCalcBlock: block
    signal tmp_Valid    : std_logic :='0';
    signal tmp_Ready    : std_logic :='0';
    signal tmp_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal tmp_rdV      : std_logic_vector(31 downto 0);
    signal tmp_rd       : std_logic_vector( 4 downto 0);
    constant rd_Base    : integer := 0;
    constant rdV_Base   : integer := rd_Base   + tmp_rd'LENGTH;
    constant ThNo_Base  : integer := rdV_Base  + tmp_rdV'LENGTH;
    constant PC_Base    : integer := ThNo_Base + tmp_ThNo'LENGTH;
    constant DATA_WIDTH : integer := PC_Base   + tmp_PC'LENGTH;
    signal tmp_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal SR1_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    PCalc: entity work.Perform_Calculations
      generic map (
        INST_ADDR_WIDTH => ADR_WIDTH,
        DATA_ADDR_WIDTH => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
      --RESET      => RESET;
        -- Input
        S_Valid  => Reg_Valid,
        S_Ready  => Reg_Ready,
        S_PC     => Reg_PC,
        S_ThNo   => Reg_ThNo,
        S_Imm12  => Reg_Imm12,
        S_rs1V   => Reg_rs1V,
        S_rs2V   => Reg_rs2V,
        S_rd     => Reg_rd,
        S_cmd    => Reg_cmd,
        -- Output
        M_Valid  => tmp_Valid,
        M_Ready  => tmp_Ready,
        M_PC     => tmp_PC,
        M_ThNo   => tmp_ThNo,
        M_rdV    => tmp_rdV,
        M_rd     => tmp_rd,
        -- Register_Commands hangs only in case of malfunctions
        Mx_Valid => open,
        Mx_Ready => '0',
        Mx_PC    => open,
        Mx_ThNo  => open
      );
    --
    tmp_Data <= tmp_PC & tmp_ThNo & tmp_rdV & tmp_rd;
    OBUFF: entity work.OutputBuffering
      generic map (
        SyncOnOutput => RandDSync,
        DATA_WIDTH   => DATA_WIDTH
      )
      port map (
        CLK     => CLK,
        RESET   => RESET,
        -- Input
        S_Valid => tmp_Valid,
        S_Ready => tmp_Ready,
        S_Data  => tmp_Data,
        -- Output
        M_Valid => SR1_Valid,
        M_Ready => SR1_Ready,
        M_Data  => SR1_Data
      );
    SR1_PC   <= SR1_Data(  tmp_PC'LENGTH+PC_Base-1   downto PC_Base);
    SR1_ThNo <= SR1_Data(tmp_ThNo'LENGTH+ThNo_Base-1 downto ThNo_Base);
    SR1_rdV  <= SR1_Data( tmp_rdV'LENGTH+rdV_Base-1  downto rdV_Base);
    SR1_rd   <= SR1_Data(  tmp_rd'LENGTH+rd_Base-1   downto rd_Base);
  end block;

  DMLSBlock: block
    signal tmp_Valid    : std_logic :='0';
    signal tmp_Ready    : std_logic :='0';
    signal tmp_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal tmp_rdV      : std_logic_vector(31 downto 0);
    signal tmp_rd       : std_logic_vector( 4 downto 0);
    constant rd_Base    : integer := 0;
    constant rdV_Base   : integer := rd_Base   + tmp_rd'LENGTH;
    constant ThNo_Base  : integer := rdV_Base  + tmp_rdV'LENGTH;
    constant PC_Base    : integer := ThNo_Base + tmp_ThNo'LENGTH;
    constant DATA_WIDTH : integer := PC_Base   + tmp_PC'LENGTH;
    signal tmp_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal SR0_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    DMLS: entity work.DataMem_LoadStore
      generic map (
        ADDR_WIDTH      => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
        CLK      => CLK,
        RESET    => RESET,
        -- Input from FunctionDMUX
        S_Valid  => Mem_Valid,
        S_Ready  => Mem_Ready,
        S_PC     => Mem_PC,
        S_ThNo   => Mem_ThNo,
        S_Imm12  => Mem_Imm12,
        S_rs1V   => Mem_rs1V,
        S_rs2V   => Mem_rs2V,
        S_rd     => Mem_rd,
        S_cmd    => Mem_cmd,
        -- Memory Write stream
        MW_Valid => MW_iValid,
        MW_Ready => MW_Ready,
        MW_ADR   => MW_ADR,
        MW_ThNo  => MW_ThNo,
        MW_DAT   => MW_DAT,
        MW_SEL   => MW_SEL,
        -- Memory Read Address stream
        MR_Valid => MR_iValid,
        MR_Ready => MR_Ready,
        MR_ADR   => MR_ADR,
        MR_ThNo  => MR_ThNo,
        -- Memory Read Response stream
        SR_Valid => SR_Valid,
        SR_Ready => SR_iReady,
        SR_DAT   => SR_DAT ,
        -- Output to store result
        M_Valid  => tmp_Valid,
        M_Ready  => tmp_Ready,
        M_PC     => tmp_PC,
        M_ThNo   => tmp_ThNo,
        M_rdV    => tmp_rdV,
        M_rd     => tmp_rd,
        -- Error Output
        Mx_Valid => DMLSErr_Valid,
        Mx_Ready => DMLSErr_Ready,
        Mx_PC    => DMLSErr_PC,
        Mx_ThNo  => DMLSErr_ThNo
      );
    --
    tmp_Data <= tmp_PC & tmp_ThNo & tmp_rdV & tmp_rd;
    OBUFF: entity work.OutputBuffering
      generic map (
        SyncOnOutput => RandDSync,
        DATA_WIDTH   => DATA_WIDTH
      )
      port map (
        CLK     => CLK,
        RESET   => RESET,
        -- Input
        S_Valid => tmp_Valid,
        S_Ready => tmp_Ready,
        S_Data  => tmp_Data,
        -- Output
        M_Valid => SR0_Valid,
        M_Ready => SR0_Ready,
        M_Data  => SR0_Data
      );
    SR0_PC       <= SR0_Data(  tmp_PC'LENGTH+PC_Base-1   downto PC_Base);
    SR0_ThNo     <= SR0_Data(tmp_ThNo'LENGTH+ThNo_Base-1 downto ThNo_Base); 
    SR0_rdV      <= SR0_Data( tmp_rdV'LENGTH+rdV_Base-1  downto rdV_Base);
    SR0_rd       <= SR0_Data(  tmp_rd'LENGTH+rd_Base-1   downto rd_Base);
    --
  end block;

  SRM: entity work.StoreResultMUX
    generic map (
      INST_ADDR_WIDTH => ADR_WIDTH,
      DATA_ADDR_WIDTH => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK      => CLK,
      RESET    => RESET,
      -- Input 0
      S0_Valid => SR0_Valid,
      S0_Ready => SR0_Ready,
      S0_PC    => SR0_PC,
      S0_ThNo  => SR0_ThNo,
      S0_rdV   => SR0_rdV,
      S0_rd    => SR0_rd,
      -- Input 1
      S1_Valid => SR1_Valid,
      S1_Ready => SR1_Ready,
      S1_PC    => SR1_PC,
      S1_ThNo  => SR1_ThNo,
      S1_rdV   => SR1_rdV,
      S1_rd    => SR1_rd,
      -- Input 2
      S2_Valid => SR2_Valid,
      S2_Ready => SR2_Ready,
      S2_PC    => SR2_PC,
      S2_ThNo  => SR2_ThNo,
      S2_rdV   => SR2_rdV,
      S2_rd    => SR2_rd,
      -- Output to store result
      M_Valid  => WRR_Valid,
      M_Ready  => WRR_Ready,
      M_PC     => WRR_PC,
      M_ThNo   => WRR_ThNo,
      M_rdV    => WRR_rdV,
      M_rd     => WRR_rd
    );

  WRRBlock: block
    signal tmp_Valid    : std_logic :='0';
    signal tmp_Ready    : std_logic :='0';
    signal tmp_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal tmp_rdV      : std_logic_vector(31 downto 0);
    signal tmp_rd       : std_logic_vector( 4 downto 0);
    signal M_Valid_i    : std_logic;
    constant ThNo_Base  : integer := 0;
    constant PC_Base    : integer := ThNo_Base + tmp_ThNo'LENGTH;
    constant DATA_WIDTH : integer := PC_Base   + tmp_PC'LENGTH;
    signal tmp_Data     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal M_Data       : std_logic_vector(DATA_WIDTH-1 downto 0);
  begin
    --
    WRR: entity work.WriteRegister
      generic  map (
        INST_ADDR_WIDTH => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
        CLK       => CLK,
        RESET     => RESET,
        -- Input from Instruction DMUX
        S_Valid   => WRR_Valid,
        S_Ready   => WRR_Ready,
        S_PC      => WRR_PC,
        S_ThNo    => WRR_ThNo,
        S_rdV     => WRR_rdV,
        S_rd      => WRR_rd,
        -- Stream to register write
        MW_Valid  => W2M_Valid,
        MW_Ready  => W2M_Ready, 
        MW_ADR    => W2M_ADR,
        MW_rdV    => W2M_rdV,
        -- Injection Interface
        IJ_Active => IJ_Active,
        IJ_ThNo   => IJ_ThNo,
        IJ_RegV   => IJ_RegV,
        -- Output to Function DMUX
        M_Valid   => tmp_Valid,
        M_Ready   => tmp_Ready,
        M_PC      => tmp_PC,
        M_ThNo    => tmp_ThNo
      );    
    --
    tmp_Data <= tmp_PC & tmp_ThNo;
    OBUFF: entity work.OutputBuffering
      generic map (
        SyncOnOutput => RandDSync,
        DATA_WIDTH   => DATA_WIDTH
      )
      port map (
        CLK     => CLK,
        RESET   => RESET,
        -- Input
        S_Valid => tmp_Valid,
        S_Ready => tmp_Ready,
        S_Data  => tmp_Data,
        -- Output
        M_Valid => M_iValid,
        M_Ready => M_Ready,
        M_Data  => M_Data
      );
    M_PC   <= M_Data(  tmp_PC'LENGTH+PC_Base-1   downto PC_Base);
    M_ThNo <= M_Data(tmp_ThNo'LENGTH+ThNo_Base-1 downto ThNo_Base);
    --
  end block;

  RegMem: entity work.RegisterMemory
    generic map (
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK      => CLK,
      RESET    => RESET,
      -- Input Register read
      SR_Valid => R2M_Valid,
      SR_Ready => R2M_Ready,
      SR_ADR1  => R2M_ADR1,
      SR_ADR2  => R2M_ADR2,
      SR_Sel1  => R2M_Sel1,
      SR_Sel2  => R2M_Sel2,
      -- Input Register write
      SW_Valid => W2M_Valid,
      SW_Ready => W2M_Ready,
      SW_ADR   => W2M_ADR,
      SW_rdV   => W2M_rdV,
      -- Output
      MR_Valid => M2R_Valid,
      MR_Ready => M2R_Ready,
      MR_rs1V  => M2R_rs1V,
      MR_rs2V  => M2R_rs2V
    );

  ErrMUX: entity work.ErrorMUX
    generic map (
      INST_ADDR_WIDTH => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH,
      ERR_ID_WIDTH    => ERR_ID_WIDTH
    )
    port map (
    --RESET         => RESET;
      -- Input (1) from Instruction Alignment Error
      S_IA_Valid    => InstErr_Valid,
      S_IA_Ready    => InstErr_Ready,
      S_IA_PC       => InstErr_PC,
      S_IA_ThNo     => InstErr_ThNo,
      -- Input (2) from Data Alignment Error
      S_DA_Valid    => DMLSErr_Valid,
      S_DA_Ready    => DMLSErr_Ready,   
      S_DA_PC       => DMLSErr_PC,
      S_DA_ThNo     => DMLSErr_ThNo,
      -- Input (3) from Unsupported Instruction Error
      S_UI_Valid    => IDErr_Valid,
      S_UI_Ready    => IDErr_Ready,
      S_UI_PC       => IDErr_PC,
      S_UI_ThNo     => IDErr_ThNo,
      -- Error Output
      Mx_Valid      => Mx_iValid,
      Mx_Ready      => Mx_Ready,
      Mx_PC         => Mx_PC,
      Mx_ThNo       => Mx_ThNo,
      Mx_ErrID      => Mx_ErrID   
    );

end arch;
