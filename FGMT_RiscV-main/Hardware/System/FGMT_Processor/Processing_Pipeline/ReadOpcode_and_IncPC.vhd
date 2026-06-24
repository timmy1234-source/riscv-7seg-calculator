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
-- ReadOpcode_and_IncPC
-- This pipeline stage reads the opcode and then increments the PC
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity ReadOpcode_and_IncPC is
  generic (
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    CLK       : in  std_logic;
    RESET     : in  std_logic;
    -- Input
    S_Valid   : in  std_logic;
    S_Ready   : out std_logic;
    S_PC      : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo    : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Generate Address Stream
    MI_Valid  : out std_logic;
    MI_Ready  : in  std_logic;
    MI_ADR    : out std_logic_vector(ADR_WIDTH-1 downto 1);
    MI_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Read Data Stream
    SI_Valid  : in  std_logic;
    SI_Ready  : out std_logic;
    SI_Inst   : in  std_logic_vector(31 downto 0);
    -- Output with Valid Instruction
    M_Valid   : out std_logic;
    M_Ready   : in  std_logic;
    M_PC      : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_Inst    : out std_logic_vector(31 downto 0);
    -- Output on Alignment Error
    Mx_Valid  : out std_logic;
    Mx_Ready  : in  std_logic;
    Mx_PC     : out std_logic_vector(ADR_WIDTH-1 downto 0);
    Mx_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Injection Inputs
    IJ_Active : in  std_logic;
    IJ_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    IJ_Inst   : in  std_logic_vector(31 downto 0)
  );
end ReadOpcode_and_IncPC;

library ieee;
use ieee.numeric_std.all;
architecture arch of ReadOpcode_and_IncPC is
  signal T1_Valid  : std_logic;
  signal T1_Ready  : std_logic;
  signal T1_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal T1_Inject : std_logic;
  signal T1_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal T2_Valid  : std_logic;
  signal T2_Ready  : std_logic;
  signal T2_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal T2_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal T2_PCp4   : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal T2_Inject : std_logic;
  signal T3_Valid  : std_logic;
  signal T3_Ready  : std_logic;
  signal T3_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal T3_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal T3_Inject : std_logic;
  signal T4_Valid  : std_logic;
  signal T4_Ready  : std_logic;
  signal T4_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal T4_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal T4_Inject : std_logic;
  signal T5_Valid  : std_logic;
  signal T5_Ready  : std_logic;
  signal T5_Inst   : std_logic_vector(31 downto 0);
begin

  DS_DMUX: process(S_Valid, S_PC, S_ThNo, Mx_Ready, T1_Ready)
  begin
    S_Ready  <= '0'; 
    Mx_Valid <= '0';
    Mx_PC    <= (Mx_PC'range => '-');
    Mx_ThNo  <= (Mx_ThNo'range => '-');
    T1_Valid <= '0';
    T1_PC    <= (T1_PC'range => '-');
    T1_ThNo  <= (T1_ThNo'range => '-');
    if S_PC(0)='0' then -- RiscV allows half word aligned access, thus only bit 0 is checked
      T1_Valid <= S_Valid;
      T1_PC    <= S_PC;
      T1_ThNo  <= S_ThNo;
      S_Ready  <= T1_Ready;
    elsif S_PC(0)='1' then 
      Mx_Valid <= S_Valid;
      Mx_PC    <= S_PC;
      Mx_ThNo  <= S_ThNo;
      S_Ready  <= Mx_Ready;
    end if;
  end process;

  T1_Inject <= '1' when IJ_Active='1' and (IJ_ThNo=S_ThNo) else '0';

  DS_Duplicate: block
    type States is (Run,W_T2,W_MI,Err);
    signal State     : States;
    signal NextState : States;
  begin

    T2_PC   <= T1_PC   when T1_Valid='1' else (others => '-');
    T2_ThNo <= T1_ThNo when T1_Valid='1' else (others => '-');
    -- MI_ADR  <= T1_PC(ADR_WIDTH-1 downto 1);
    MI_ADR  <= T1_PC(ADR_WIDTH-1 downto 1) when T1_Valid='1' else (others => '-');
    MI_ThNo <= T1_ThNo when T1_Valid='1' else (others => '-');
  
    Next_and_Mealy: process(State, RESET, T1_Valid, T1_Inject, T2_Ready, MI_Ready)
    begin
      NextState <= Err;
      T1_Ready <= '0';
      T2_Valid <= '0';
      T2_Inject <= '0';
      MI_Valid <= '0';
      if RESET='1' then
        NextState <= Run;
      elsif RESET='0' then
        case State is
          when Run  =>
            if (T1_valid='0') then
              NextState <= Run;
            elsif (T1_valid='1') and (T1_Inject='0') then
              MI_Valid <= '1';
              T2_Valid <= '1';
              if (MI_Ready='1') and (T2_Ready='1') then
                NextState <= Run;
                T1_Ready <= '1';
              elsif (MI_Ready='0') and (T2_Ready='0') then
                NextState <= Run;
              elsif (MI_Ready='1') and (T2_Ready='0') then
                NextState <= W_T2;
              elsif (MI_Ready='0') and (T2_Ready='1') then
                NextState <= W_MI;
              end if;
            elsif (T1_valid='1') and (T1_Inject='1') then
              NextState <= Run;
              T2_Valid  <= '1';
              T2_Inject <= '1';
              if (T2_Ready='1') then
                T1_Ready <= '1';
              elsif (T2_Ready='0') then
                null;
              end if;
            end if;
          when W_T2 =>
            if (T1_valid='1') then
              T2_Valid <= '1';
              if (T2_Ready='0') then
                NextState <= W_T2;
              elsif (T2_Ready='1') then
                NextState <= Run;
                T1_Ready <= '1';
              end if;
            end if;
          when W_MI =>
            if (T1_valid='1') then
              MI_Valid <= '1';
              if (MI_Ready='0') then
                NextState <= W_MI;
              elsif (MI_Ready='1') then
                NextState <= Run;
                T1_Ready <= '1';
              end if;
            end if;
          when Err  =>
            T1_Ready  <= 'X';
            T2_Inject <= 'X';
            T2_Valid  <= 'X';
            MI_Valid  <= 'X';
        end case;
      end if;
    end process;
    
    StateReg: process(CLK)
    begin
      if rising_edge(CLK) then
        State <= NextState;
      end if;
    end process;
    
  end block;

  process (T2_PC)
    variable Inc_PC : unsigned(T2_PC'range);
  begin
    Inc_PC := unsigned(T2_PC)+4;
    for i in T2_PCp4'range loop
      if (Inc_PC(i)='0') or (Inc_PC(i)='1') then T2_PCp4(i) <= Inc_PC(i);
      else                                       T2_PCp4(i) <= '-';
      end if;
    end loop;
  end process;

  DS_ReadySync_T2: block
    constant With_Ready_Sync : boolean := true;
    signal in_ready   : std_logic := '0';
    signal reg_valid  : std_logic := '0';
    signal reg_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal reg_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal reg_Inject : std_logic := '0';
    signal mux_valid  : std_logic := '0';
  begin
    WRS: if With_Ready_Sync generate
      Reg: process(CLK)
      begin
        if rising_edge(CLK) then
          if in_ready='1' then
            reg_valid  <= T2_Valid;
            reg_PC     <= T2_PCp4;
            reg_ThNo   <= T2_ThNo;
            reg_Inject <= T2_Inject;
          end if;
          in_ready <= (not mux_valid) or T3_Ready;
        end if;
      end process;
      mux_valid <= T2_Valid  when in_ready='1' else
                   reg_valid when in_ready='0' else
                   '-';
      T3_Valid  <= mux_valid;
      T3_PC     <= T2_PCp4 when in_ready='1' else
                   reg_PC  when in_ready='0' else
                   (T3_PC'range => '-');
      T3_ThNo   <= T2_ThNo      when in_ready='1' else
                   reg_ThNo     when in_ready='0' else
                   (T3_ThNo'range => '-');
      T3_Inject <= T2_Inject  when in_ready='1' else
                   reg_Inject when in_ready='0' else
                   '-';
      T2_Ready <= in_ready;
    end generate;
    nWRS:if not With_Ready_Sync generate
      T3_Valid  <= T2_Valid;
      T3_PC     <= T2_PCp4;
      T3_ThNo   <= T2_ThNo;
      T3_Inject <= T2_Inject;
      T2_Ready  <= T3_Ready;
    end generate;
  end block;
  
  DS_block:block
    constant With_DataSync : boolean := false;
  begin  
    WDS:if With_DataSync generate
      DS_DataSync: process(CLK)
      begin
        if rising_edge(CLK) then
          if    RESET='1' then
            T4_Valid  <= '0';
            T4_PC     <= (T4_PC'range => '-');
            T4_ThNo   <= (T4_ThNo'range => '-');
            T4_Inject <= '0';
          elsif (RESET='0') and (T3_Ready='1') then
            T4_Valid  <= T3_Valid;
            T4_PC     <= T3_PC;
            T4_ThNo   <= T3_ThNo;
            T4_Inject <= T3_Inject;
          end if;
        end if;
      end process;
      T3_Ready <= '1' when T4_Ready='1' else
                  '1' when T4_Valid='0' else
                  '0' when (T4_Ready='0') and (T4_Valid='1') else
                  '-';
    end generate;
    nWDS:if not With_DataSync generate
      T4_Valid  <= T3_Valid;
      T4_PC     <= T3_PC;
      T4_ThNo   <= T3_ThNo;
      T4_Inject <= T3_Inject;
      T3_Ready  <= T4_Ready;
    end generate;
  end block;
  
  DS_ReadySync_SI: block
    constant With_Ready_Sync : boolean := true;
    signal in_ready  : std_logic := '0';
    signal reg_valid : std_logic := '0';
    signal reg_inst  : std_logic_vector(31 downto 0);
    signal mux_valid : std_logic := '0';
  begin
    WRS:if With_Ready_Sync generate
      Reg: process(CLK)
      begin
        if rising_edge(CLK) then
          if in_ready='1' then
            reg_valid <= SI_Valid;
            reg_inst  <= SI_Inst;
          end if;
          in_ready <= (not mux_valid) or T5_Ready;
        end if;
      end process;
      mux_valid <= SI_Valid  when in_ready='1' else
                   reg_valid when in_ready='0' else
                   '-';
      T5_Valid  <= mux_valid;
      T5_Inst   <= SI_Inst  when in_ready='1' else
                   reg_inst when in_ready='0' else
                   (T5_Inst'range => '-');
      SI_Ready <= in_ready;
    end generate;
    nWRS:if not With_Ready_Sync generate
      T5_Valid <= SI_Valid;
      T5_Inst  <= SI_Inst;
      SI_Ready <= T5_Ready;
    end generate;
    
  end block;
  
  DS_Merge: process(T4_Valid, T4_PC, T4_ThNo, T4_Inject, T5_Valid, T5_Inst, M_Ready, IJ_Inst) 
  begin
    T4_Ready <= '0';
    T5_Ready <= '0';
    M_Valid  <= '0';
    M_PC     <= T4_PC;
    M_ThNo   <= T4_ThNo;
    M_Inst   <= (M_Inst'range => '-');
    if (T4_Valid='1') and (T4_Inject='0') and (T5_Valid='1')  then
      T4_Ready <= M_Ready;
      T5_Ready <= M_Ready;
      M_Inst   <= T5_Inst;
      M_Valid  <= '1';
    elsif (T4_Valid='1') and (T4_Inject='1') then
      T4_Ready <= M_Ready;
      M_Inst   <= IJ_Inst;
      M_Valid  <= '1';
    end if;
  end process;
  
end arch;