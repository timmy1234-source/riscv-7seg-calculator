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
-- ReadRegisters
-- This pipeline stage reads the source register values, if required,
-- from the register file
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity ReadRegisters is 
  generic (
    INST_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  5
  );
  port (
    CLK      : in  std_logic;
    RESET    : in  std_logic;
    -- Input from Instruction DMUX
    S_Valid  : in  std_logic;
    S_Ready  : out std_logic;
    S_PC     : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_Imm12  : in  std_logic_vector(11 downto 0);
    S_rs1    : in  std_logic_vector( 4 downto 0);
    S_rs2    : in  std_logic_vector( 4 downto 0);
    S_rd     : in  std_logic_vector( 4 downto 0);
    S_cmd    : in  std_logic_vector(10 downto 0);
    -- Stream to register read
    MR_Valid : out std_logic;
    MR_Ready : in  std_logic;
    MR_ADR1  : out std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
    MR_ADR2  : out std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
    MR_Sel1  : out std_logic;
    MR_Sel2  : out std_logic;
    -- Stream from register read
    SR_Valid : in  std_logic;
    SR_Ready : out std_logic;
    SR_rs1V  : in  std_logic_vector(31 downto 0);
    SR_rs2V  : in  std_logic_vector(31 downto 0);
    -- Output to Function DMUX
    M_Valid  : out std_logic;
    M_Ready  : in  std_logic;
    M_PC     : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_Imm12  : out std_logic_vector(11 downto 0);
    M_rs1V   : out std_logic_vector(31 downto 0);
    M_rs2V   : out std_logic_vector(31 downto 0);
    M_rd     : out std_logic_vector( 4 downto 0);
    M_cmd    : out std_logic_vector(10 downto 0)
  );
end ReadRegisters;

library ieee;
use ieee.numeric_std.all;
architecture arch of ReadRegisters is
  signal RSR_Valid   : std_logic;
  signal RSR_Ready   : std_logic;
  signal DS_Valid    : std_logic := '0';
  signal DS_Ready    : std_logic := '0';
  signal DS_PC       : std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
  signal DS_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal DS_Imm12    : std_logic_vector(11 downto 0);
  signal DS_rs1_gt0  : std_logic;
  signal DS_rs2_gt0  : std_logic;
  signal DS_rd       : std_logic_vector( 4 downto 0);
  signal DS_cmd      : std_logic_vector(10 downto 0);
  signal rs1_gt0     : std_logic;
  signal rs2_gt0     : std_logic;
begin

  rs1_gt0 <= '1' when unsigned(S_rs1)>0 else '0';
  rs2_gt0 <= '1' when unsigned(S_rs2)>0 else '0';

  MR_ADR1 <= S_ThNo & S_rs1;
  MR_Sel1 <= rs1_gt0;
  MR_ADR2 <= S_ThNo & S_rs2;
  MR_Sel2 <= rs2_gt0;

  FSM: block
    type States is (RdSrcReg, RSR_Wait, MR_Wait, error);
    signal State      : States;
    signal NextState  : States;
  begin
    process (State, RESET, S_Valid, rs1_gt0, rs2_gt0, MR_Ready, RSR_Ready)
    begin
      NextState  <= error;
      S_Ready    <= '0';
      MR_Valid   <= '0';
      RSR_Valid  <= '0';
      if RESET='1' then
        NextState  <= RdSrcReg;
      elsif RESET='0' then
        case State is
          when RdSrcReg =>
            if (S_Valid='0') then
              NextState <= RdSrcReg;
            elsif (S_Valid='1') and (rs1_gt0='0') and (rs2_gt0='0') then
              NextState <= RdSrcReg;
              RSR_Valid <='1';
              if (RSR_Ready='1') then
                S_Ready <='1';
              end if;
            elsif (S_Valid='1') and ((rs1_gt0='1') or (rs2_gt0='1')) then
              RSR_Valid <='1';
              MR_Valid  <='1';
              if    (MR_Ready='0') and (RSR_Ready='0') then
                NextState <= RdSrcReg;
              elsif (MR_Ready='0') and (RSR_Ready='1') then
                NextState <= MR_Wait;
              elsif (MR_Ready='1') and (RSR_Ready='0') then
                NextState <= RSR_Wait;
              elsif (MR_Ready='1') and (RSR_Ready='1') then
                NextState <= RdSrcReg;
                S_Ready   <='1';
              end if;
            end if;
          when RSR_Wait =>
              RSR_Valid <= '1';
            if (RSR_Ready='0') then
              NextState <= RSR_Wait;
            elsif (RSR_Ready='1') then
              NextState <= RdSrcReg;
              S_Ready   <='1';
            end if;
          when MR_Wait =>
              MR_Valid  <= '1';
            if (MR_Ready='0') then
              NextState <= MR_Wait;
            elsif (MR_Ready='1') then
              NextState <= RdSrcReg;
              S_Ready   <='1';
            end if;
          when error => null;
        end case;
      end if;      
    end process;

    process (CLK)
    begin
      if rising_edge(CLK) then
        State <= NextState;
      end if;
    end process;

  end block;

  DS_Sync_Ld: block
    constant With_Ready_Sync : boolean := true;
  begin
    WRS:if With_Ready_Sync generate
      signal in_ready    : std_logic := '0';
      signal mux_valid   : std_logic := '0';
      signal reg_valid   : std_logic := '0';
      signal reg_PC      : std_logic_vector(S_PC'range);
      signal reg_ThNo    : std_logic_vector(S_ThNo'range);
      signal reg_Imm12   : std_logic_vector(S_Imm12'range);
      signal reg_rd      : std_logic_vector(S_rd'range);
      signal reg_cmd     : std_logic_vector(S_cmd'range);
      signal reg_rs1_gt0 : std_logic;
      signal reg_rs2_gt0 : std_logic;
    begin
      Reg: process(CLK)
      begin
        if rising_edge(CLK) then
          if in_ready='1' then
            reg_valid    <= RSR_Valid;
            reg_PC       <= S_PC;
            reg_ThNo     <= S_ThNo;
            reg_Imm12    <= S_Imm12;
            reg_rd       <= S_rd; 
            reg_cmd      <= S_cmd;
            reg_rs1_gt0  <= rs1_gt0;
            reg_rs2_gt0  <= rs2_gt0;
          end if;
          in_ready <= (not mux_valid) or DS_Ready;
        end if;
      end process;
      mux_valid  <= RSR_Valid   when in_ready='1' else
                    reg_valid   when in_ready='0' else
                    '-';
      DS_Valid   <= mux_valid;
      DS_PC      <= S_PC        when in_ready='1' else
                    reg_PC      when in_ready='0' else
                    (S_PC'range => '-');
      DS_ThNo    <= S_ThNo      when in_ready='1' else
                    reg_ThNo    when in_ready='0' else
                    (S_ThNo'range => '-');
      DS_Imm12   <= S_Imm12     when in_ready='1' else
                    reg_Imm12   when in_ready='0' else
                    (S_Imm12'range => '-');
      DS_rd      <= S_rd        when in_ready='1' else
                    reg_rd      when in_ready='0' else
                    (S_rd'range => '-'); 
      DS_cmd     <= S_cmd       when in_ready='1' else
                    reg_cmd     when in_ready='0' else
                    (S_cmd'range => '-');
      DS_rs1_gt0 <= rs1_gt0     when in_ready='1' else
                    reg_rs1_gt0 when in_ready='0' else
                    '-';
      DS_rs2_gt0 <= rs2_gt0     when in_ready='1' else
                    reg_rs2_gt0 when in_ready='0' else
                    '-';
      RSR_Ready <= in_ready;
    end generate;
    NRS:if not With_Ready_Sync generate
      DS_DataSync: process (CLK)
      begin
        if rising_edge(CLK) then
          if RSR_Ready='1' then
            DS_Valid    <= RSR_Valid;
            DS_PC       <= S_PC;
            DS_ThNo     <= S_ThNo;
            DS_Imm12    <= S_Imm12;
            DS_rd       <= S_rd; 
            DS_cmd      <= S_cmd;
            DS_rs1_gt0  <= rs1_gt0;
            DS_rs2_gt0  <= rs2_gt0;
          end if;
        end if;
      end process;
      RSR_Ready <= DS_Ready or (not DS_Valid);
    end generate;
  end block;

  DS_Merge: process(DS_Valid, DS_rs1_gt0, DS_rs2_gt0, SR_Valid, SR_rs1V, SR_rs2V, M_Ready)
  begin
    M_Valid  <= '0';
    M_rs1V   <= (M_rs1V'range => '0');
    M_rs2V   <= (M_rs2V'range => '0');
    DS_Ready <= '0';
    SR_Ready <= '0';
    if (DS_rs1_gt0='0') and (DS_rs2_gt0='0') then
      if (DS_Valid='1') then
        M_Valid  <= '1';
        DS_Ready <= M_Ready;
      end if;
    elsif (DS_rs1_gt0='1') or (DS_rs2_gt0='1') then
      if (DS_Valid='1') and (SR_Valid='1') then
        M_Valid  <= '1';
        DS_Ready <= M_Ready;
        SR_Ready <= M_Ready;
        if (DS_rs1_gt0='1') then M_rs1V <= SR_rs1V; end if;
        if (DS_rs2_gt0='1') then M_rs2V <= SR_rs2V; end if;
      end if;
    end if;
  end process;
  M_PC       <= DS_PC;
  M_ThNo     <= DS_ThNo;
  M_Imm12    <= DS_Imm12;
  M_rd       <= DS_rd;
  M_cmd      <= DS_cmd;

end arch;