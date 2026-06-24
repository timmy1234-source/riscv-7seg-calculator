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
-- DataMem_LoadStore
-- This pipeline stage acesses the external data memory 
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity DataMem_LoadStore is
  generic (
    ADDR_WIDTH      : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    CLK      : in  std_logic;
    RESET    : in  std_logic;
    -- Input
    S_Valid  : in  std_logic;
    S_Ready  : out std_logic;
    S_PC     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    S_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_Imm12  : in  std_logic_vector(11 downto 0);
    S_rs1V   : in  std_logic_vector(31 downto 0);
    S_rs2V   : in  std_logic_vector(31 downto 0);
    S_rd     : in  std_logic_vector( 4 downto 0);
    S_cmd    : in  std_logic_vector(10 downto 0);
    -- Memory Write Stream
    MW_Valid : out std_logic;
    MW_Ready : in  std_logic;
    MW_ADR   : out std_logic_vector(ADDR_WIDTH-1 downto 2);
    MW_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    MW_DAT   : out std_logic_vector(31 downto 0);
    MW_SEL   : out std_logic_vector( 3 downto 0);
    -- Memory Read Address Stream
    MR_Valid : out std_logic;
    MR_Ready : in  std_logic;
    MR_ADR   : out std_logic_vector(ADDR_WIDTH-1 downto 2);
    MR_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Memory Read Response Stream
    SR_Valid : in  std_logic;
    SR_Ready : out std_logic;
    SR_DAT   : in  std_logic_vector(31 downto 0);
    -- Output to store result
    M_Valid  : out std_logic;
    M_Ready  : in  std_logic;
    M_PC     : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    M_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_rdV    : out std_logic_vector(31 downto 0);
    M_rd     : out std_logic_vector( 4 downto 0);
    -- Error Output
    Mx_Valid : out std_logic;
    Mx_Ready : in  std_logic;
    Mx_PC    : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    Mx_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end DataMem_LoadStore;

library ieee;
use ieee.numeric_std.all;
architecture arch of DataMem_LoadStore is
  --
  signal ADR     : std_logic_vector(31 downto 0);
  type   CodeT is (none, W, H_2, H_0, B_3, B_2, B_1, B_0, HU_2, HU_0, BU_3, BU_2, BU_1, BU_0);
  signal Code    : CodeT;
  --
  signal WSy_Valid : std_logic;
  signal WSy_Ready : std_logic;
  --
  signal RSy_Valid : std_logic;
  signal RSy_Ready : std_logic;
  --
  signal Rd_Valid  : std_logic;
  signal Rd_Ready  : std_logic;
  signal Rd_Code   : CodeT;
  signal Rd_rd     : std_logic_vector( 4 downto 0);
  signal Rd_PC     : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal Rd_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  --
  signal Ld_Valid  : std_logic;
  signal Ld_Ready  : std_logic;
  signal Ld_DAT    : std_logic_vector(31 downto 0);
  signal Ld_Code   : CodeT;
  signal Ld_rd     : std_logic_vector( 4 downto 0);
  signal Ld_PC     : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal Ld_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal Ld_rdV    : std_logic_vector(31 downto 0);
  --
  signal St_Valid  : std_logic;
  signal St_Ready  : std_logic;
  signal St_rd     : std_logic_vector( 4 downto 0);
  signal St_rdV    : std_logic_vector(31 downto 0);
  signal St_PC     : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal St_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  --
begin

  ADR     <= std_logic_vector(signed(S_rs1V) + signed(S_Imm12));
  MW_ADR  <= ADR(ADDR_WIDTH-1 downto 2);
  MW_ThNo <= S_ThNo;
  MR_ADR  <= ADR(ADDR_WIDTH-1 downto 2);
  MR_ThNo <= S_ThNo;

  InAlign: process(S_rs2V,Code)
    constant DontCares : std_logic_vector(31 downto 0) := (others => '-');
  begin
    case(Code) is
      when W    => MW_DAT <= S_rs2V;
      when H_2  => MW_DAT <= S_rs2V(15 downto 0)     & DontCares(15 downto 0);
      when H_0  => MW_DAT <= DontCares(31 downto 16) & S_rs2V(15 downto 0);
      when B_3  => MW_DAT <= S_rs2V(7 downto 0)      & DontCares(23 downto 0);
      when B_2  => MW_DAT <= DontCares(31 downto 24) & S_rs2V(7 downto 0) & DontCares(15 downto 0);
      when B_1  => MW_DAT <= DontCares(31 downto 16) & S_rs2V(7 downto 0) & DontCares( 7 downto 0);
      when B_0  => MW_DAT <= DontCares(31 downto  8) & S_rs2V(7 downto 0);
      when HU_2 => MW_DAT <= DontCares;
      when HU_0 => MW_DAT <= DontCares;
      when BU_3 => MW_DAT <= DontCares;
      when BU_2 => MW_DAT <= DontCares;
      when BU_1 => MW_DAT <= DontCares;
      when BU_0 => MW_DAT <= DontCares;
      when none => MW_DAT <= DontCares;
    end case;
  end process;
  
  FSM: block is
    type   states is (LoadStore, MW_Wait, WSy_Wait, MR_Wait, RSy_Wait, WAlignError, RAlignError, Error);
    signal State     : states := LoadStore;
    signal NextState : states;
  begin
  
    NextState_and_Mealy: process(State,RESET, S_Valid,ADR(1 downto 0),S_cmd,MW_Ready,MR_Ready,RSy_Ready,WSy_Ready,Mx_Ready)
      constant cmd_LB    : std_logic_vector(10 downto 0) := "00000000011";
      constant cmd_LH    : std_logic_vector(10 downto 0) := "00010000011";
      constant cmd_LW    : std_logic_vector(10 downto 0) := "00100000011";
      constant cmd_LBU   : std_logic_vector(10 downto 0) := "01000000011";
      constant cmd_LHU   : std_logic_vector(10 downto 0) := "01010000011";
      constant cmd_SB    : std_logic_vector(10 downto 0) := "00000100011";
      constant cmd_SH    : std_logic_vector(10 downto 0) := "00010100011";
      constant cmd_SW    : std_logic_vector(10 downto 0) := "00100100011";
      variable WriteIssued : boolean;
      variable ReadIssued  : boolean;
    begin
      NextState   <= Error;
      S_Ready     <= '0';
      MW_SEL      <= "----";
      Code        <= none;
      MW_Valid    <= '0';
      MR_Valid    <= '0';
      WSy_Valid   <= '0';
      RSy_Valid   <= '0';
      WriteIssued := false;
      ReadIssued  := false;
      if RESET='1' then
        NextState   <= LoadStore;
      elsif RESET='0' then
        case State is
          when LoadStore =>
            ----- No valid instruction
            if S_Valid='0' then
              NextState <= LoadStore;
            elsif (S_Valid='1') then
              -----------------------------------------------------------------------------------------------------------
              --- Write Alignment errors
              -----------------------------------------------------------------------------------------------------------
              if    ((s_cmd=cmd_SW) and (ADR(1 downto 0)/="00"))
                 or ((s_cmd=cmd_SH) and (ADR(1 downto 0) ="01"))
                 or ((s_cmd=cmd_SH) and (ADR(1 downto 0) ="11")) then
                NextState <= WAlignError;
                --S_Ready <= '1';
              -----------------------------------------------------------------------------------------------------------
              --- Store
              -----------------------------------------------------------------------------------------------------------
              elsif (S_cmd=cmd_SW)and (ADR(1 downto 0)="00")  then
                ----- SW instruction
                WSy_Valid <= '1';
                MW_Valid  <= '1';
                Code      <= W;
                MW_SEL    <= "1111";
                WriteIssued := true;
              elsif (S_cmd=cmd_SH) then
                ----- SH instruction
                WSy_Valid <= '1';
                MW_Valid  <= '1';
                if (ADR(1 downto 0)="00") then
                  -- Writing Bytes 0 and 1 of memory word
                  Code   <= H_0;
                  MW_SEL <= "0011";
                  WriteIssued := true;
                elsif (ADR(1 downto 0)="10") then
                  -- Writing Bytes 2 and 3 of memory word
                  Code   <= H_2;
                  MW_SEL <= "1100";
                  WriteIssued := true;
                end if;
              elsif (S_cmd=cmd_SB) then
                ----- SB instruction
                WSy_Valid <= '1';
                MW_Valid  <= '1';
                if (ADR(1 downto 0)="00") then
                  -- Writing Byte 0 of memory word
                  Code   <= B_0;
                  MW_SEL <= "0001";
                  WriteIssued := true;
                elsif (ADR(1 downto 0)="01") then
                  -- Writing Byte 1 of memory word
                  Code   <= B_1;
                  MW_SEL <= "0010";
                  WriteIssued := true;
                elsif (ADR(1 downto 0)="10") then
                  -- Writing Byte 2 of memory word
                  Code   <= B_2;
                  MW_SEL <= "0100";
                  WriteIssued := true;
                elsif (ADR(1 downto 0)="11") then
                  -- Writing Byte 3 of memory word
                  Code   <= B_3;
                  MW_SEL <= "1000";
                  WriteIssued := true;
                end if;
              -----------------------------------------------------------------------------------------------------------
              --- Read Alignment errors
              -----------------------------------------------------------------------------------------------------------
              elsif ((S_valid='1') and (s_cmd=cmd_LW) and (ADR(1 downto 0)/="00"))
                 or ((S_valid='1') and (s_cmd=cmd_LH) and (ADR(1 downto 0) ="01"))
                 or ((S_valid='1') and (s_cmd=cmd_LH) and (ADR(1 downto 0) ="11")) then
                NextState <= RAlignError;
                --S_Ready <= '1';
              -----------------------------------------------------------------------------------------------------------
              --- Load
              -----------------------------------------------------------------------------------------------------------
              elsif (S_cmd=cmd_LW) and (ADR(1 downto 0)="00") then
                ----- LW instruction
                RSy_Valid  <= '1';
                MR_Valid   <= '1';
                Code       <= W;
                ReadIssued := true;
              elsif S_cmd=cmd_LH then 
                ----- LH instruction
                RSy_Valid  <= '1';
                MR_Valid   <= '1';
                if (ADR(1 downto 0)="00") then
                  Code <= H_0;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="10") then
                  Code <= H_2;
                  ReadIssued := true;
                end if;
              elsif S_cmd=cmd_LHU then 
                ----- LHU instruction
                RSy_Valid  <= '1';
                MR_Valid   <= '1';
                if (ADR(1 downto 0)="00") then
                  Code <= HU_0;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="10") then
                  Code <= HU_2;
                  ReadIssued := true;
                end if;
              elsif S_cmd=cmd_LB then
                ----- LB instruction
                RSy_Valid  <= '1';
                MR_Valid   <= '1';
                if (ADR(1 downto 0)="00") then
                  Code <= B_0;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="01") then
                  Code <= B_1;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="10") then
                  Code <= B_2;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="11") then
                  Code <= B_3;
                  ReadIssued := true;
                end if;
              elsif S_cmd=cmd_LBU then
                ----- LBU instruction
                RSy_Valid  <= '1';
                MR_Valid   <= '1';
                if (ADR(1 downto 0)="00") then
                  Code <= BU_0;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="01") then
                  Code <= BU_1;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="10") then
                  Code <= BU_2;
                  ReadIssued := true;
                elsif (ADR(1 downto 0)="11") then
                  Code <= BU_3;
                  ReadIssued := true;
                end if;
              else
                -----------------------------------------------------------------------------------------------------------
                --- Unexpected inputs
                -----------------------------------------------------------------------------------------------------------
                RSy_Valid  <= '0';
                MR_Valid   <= '0';
                NextState <= Error;
              end if;
              if WriteIssued then
                if    (MW_Ready='0') and (WSy_Ready='0') then
                  NextState <= LoadStore;
                elsif (MW_Ready='0') and (WSy_Ready='1') then
                  NextState <= MW_Wait;
                elsif (MW_Ready='1') and (WSy_Ready='0') then
                  NextState <= WSy_Wait;
                elsif (MW_Ready='1') and (WSy_Ready='1') then
                  NextState <= LoadStore;
                  S_Ready <= '1';
                end if;
              end if;
              if ReadIssued then
                if    (MR_Ready='0') and (RSy_Ready='0') then
                  NextState <= LoadStore;
                elsif (MR_Ready='0') and (RSy_Ready='1') then
                  NextState <= MR_Wait;
                elsif (MR_Ready='1') and (RSy_Ready='0') then
                  NextState <= RSy_Wait;
                elsif (MR_Ready='1') and (RSy_Ready='1') then
                  NextState <= LoadStore;
                  S_Ready <= '1';
                end if;
              end if;
            end if;
          when MW_Wait =>
            MW_Valid <= '1';
            if (S_cmd=cmd_SW)and (ADR(1 downto 0)="00")  then
              ----- SW instruction
              Code      <= W;
              MW_SEL    <= "1111";
            elsif (S_cmd=cmd_SH) then
              ----- SH instruction
              if (ADR(1 downto 0)="00") then
                -- Writing Bytes 0 and 1 of memory word
                Code   <= H_0;
                MW_SEL <= "0011";
              elsif (ADR(1 downto 0)="10") then
                -- Writing Bytes 2 and 3 of memory word
                Code   <= H_2;
                MW_SEL <= "1100";
              end if;
            elsif (S_cmd=cmd_SB) then
              ----- SB instruction
              if (ADR(1 downto 0)="00") then
                -- Writing Byte 0 of memory word
                Code   <= B_0;
                MW_SEL <= "0001";
              elsif (ADR(1 downto 0)="01") then
                -- Writing Byte 1 of memory word
                Code   <= B_1;
                MW_SEL <= "0010";
              elsif (ADR(1 downto 0)="10") then
                -- Writing Byte 2 of memory word
                Code   <= B_2;
                MW_SEL <= "0100";
              elsif (ADR(1 downto 0)="11") then
                -- Writing Byte 3 of memory word
                Code   <= B_3;
                MW_SEL <= "1000";
              end if;
            end if;
            if MW_Ready='0'  then
              NextState <= MW_Wait;
            elsif MW_Ready='1' then
              NextState <= LoadStore;
              S_Ready  <= '1';
            end if;
          when WSy_Wait =>
            WSy_Valid <= '1';
            if WSy_Ready='0'  then
              NextState <= WSy_Wait;
            elsif WSy_Ready='1' then
              NextState <= LoadStore;
              S_Ready   <= '1';
            end if;
          when MR_Wait =>
            MR_Valid <= '1';
            if MR_Ready='0'  then
              NextState <= MR_Wait;
            elsif MR_Ready='1' then
              NextState <= LoadStore;
              S_Ready  <= '1';
            end if;
          when RSy_Wait =>
            RSy_Valid <= '1';
            if (S_cmd=cmd_LW) and (ADR(1 downto 0)="00") then
              ----- LW instruction
              Code   <= W;
            elsif S_cmd=cmd_LH then 
              ----- LH instruction
              if (ADR(1 downto 0)="00") then
                Code <= H_0;
              elsif (ADR(1 downto 0)="10") then
                Code <= H_2;
              end if;
            elsif S_cmd=cmd_LHU then 
              ----- LHU instruction
              if (ADR(1 downto 0)="00") then
                Code <= HU_0;
              elsif (ADR(1 downto 0)="10") then
                Code <= HU_2;
              end if;
            elsif S_cmd=cmd_LB then
              ----- LB instruction
              if (ADR(1 downto 0)="00") then
                Code <= B_0;
              elsif (ADR(1 downto 0)="01") then
                Code <= B_1;
              elsif (ADR(1 downto 0)="10") then
                Code <= B_2;
              elsif (ADR(1 downto 0)="11") then
                Code <= B_3;
              end if;
            elsif S_cmd=cmd_LBU then
              ----- LBU instruction
              if (ADR(1 downto 0)="00") then
                Code <= BU_0;
              elsif (ADR(1 downto 0)="01") then
                Code <= BU_1;
              elsif (ADR(1 downto 0)="10") then
                Code <= BU_2;
              elsif (ADR(1 downto 0)="11") then
                Code <= BU_3;
              end if;
            end if;
            if RSy_Ready='0'  then
              NextState <= RSy_Wait;
            elsif RSy_Ready='1' then
              NextState <= LoadStore;
              S_Ready   <= '1';
            end if;
          when WAlignError =>
            if (Mx_ready='0') then 
              NextState <= WAlignError;
            elsif (Mx_ready='1') then 
              NextState <= LoadStore;
              S_Ready <= '1';
            end if;
          when RAlignError =>
            if (Mx_ready='0') then 
              NextState <= RAlignError;
            elsif (Mx_ready='1') then 
              NextState <= LoadStore;
              S_Ready <= '1';
            end if;
          when Error =>
            null;
        end case;
      end if;
    end process;
    
    StateReg_and_Moore: process(CLK)
    begin
      if rising_edge(CLK) then
        State <= NextState;
        case NextState is
          when LoadStore   => Mx_Valid <= '0';
          when MW_Wait     => Mx_Valid <= '0';
          when WSy_Wait    => Mx_Valid <= '0';
          when MR_Wait     => Mx_Valid <= '0';
          when RSy_Wait    => Mx_Valid <= '0';
          when WAlignError => Mx_Valid <= '1';
          when RAlignError => Mx_Valid <= '1';
          when Error       => Mx_Valid <= '0';
        end case;
      end if;
    end process;
    
  end block;
  
  Mx_PC       <= S_PC;
  Mx_ThNo     <= S_ThNo;

  DS_Sync_St: block
    constant With_Ready_Sync : boolean := true;
  begin
    WRS:if With_Ready_Sync generate
      signal in_ready  : std_logic := '0';
      signal reg_valid : std_logic := '0';
      signal reg_rd    : std_logic_vector(S_rd'range);
      signal reg_PC    : std_logic_vector(S_PC'range);
      signal reg_ThNo  : std_logic_vector(S_ThNo'range);
      signal mux_valid : std_logic := '0';
    begin
      Reg: process(CLK)
      begin
        if rising_edge(CLK) then
          if in_ready='1' then
            reg_valid <= WSy_Valid;
            reg_rd    <= S_rd;
            reg_PC    <= S_PC;
            reg_ThNo  <= S_ThNo;
          end if;
          in_ready <= (not mux_valid) or St_Ready;
        end if;
      end process;
      mux_valid <= WSy_Valid when in_ready='1' else
                   reg_valid when in_ready='0' else
                   '-';
      St_Valid <= mux_valid;
      St_rd    <= S_rd   when in_ready='1' else
                  reg_rd when in_ready='0' else
                  (St_rd'range => '-');
      St_rdV   <= (St_rdV'range => '-');
      St_PC    <= S_PC   when in_ready='1' else
                  reg_PC when in_ready='0' else
                  (St_PC'range => '-');
      St_ThNo  <= S_ThNo   when in_ready='1' else
                  reg_ThNo when in_ready='0' else
                  (St_ThNo'range => '-');
      WSy_Ready <= in_ready;
    end generate;
    NRS:if not With_Ready_Sync generate
      St_DataSync: process(CLK)
        variable Valid : std_logic := '0';
      begin
        if rising_edge(CLK) then
          if RESET='1' then
            Valid       := '0';
            St_rd       <= (St_rd'range => '-');
            St_rdV      <= (St_rdV'range => '-');
            St_PC       <= (St_PC'range => '-');
            St_ThNo     <= (St_ThNo'range => '-');
          elsif WSy_Ready='1' then
            Valid       := WSy_Valid;
            St_rd       <= S_rd;
            St_rdV      <= (St_rdV'range => '-');
            St_PC       <= S_PC;
            St_ThNo     <= S_ThNo;
          end if;
          St_Valid <= Valid;
        end if;
      end process;
      WSy_Ready <= (not St_Valid) or St_Ready;
    end generate;
  end block;

  DS_Sync_Ld: block
    constant With_Ready_Sync : boolean := true;
  begin
    WRS:if With_Ready_Sync generate
      signal in_ready  : std_logic := '0';
      signal reg_valid : std_logic := '0';
      signal reg_rd     : std_logic_vector(S_rd'range);
      signal reg_Code   : CodeT;
      signal reg_PC     : std_logic_vector(S_PC'range);
      signal reg_ThNo   : std_logic_vector(S_ThNo'range);
      signal mux_valid : std_logic := '0';
    begin
      Reg: process(CLK)
      begin
        if rising_edge(CLK) then
          if in_ready='1' then
            reg_valid <= RSy_Valid;
            reg_rd    <= S_rd;
            reg_Code  <= Code;
            reg_PC    <= S_PC;
            reg_ThNo  <= S_ThNo;
          end if;
          in_ready <= (not mux_valid) or Rd_Ready;
        end if;
      end process;
      mux_valid <= RSy_Valid when in_ready='1' else
                   reg_valid when in_ready='0' else
                   '-';
      Rd_Valid  <= mux_valid;
      Rd_rd     <= S_rd     when in_ready='1' else
                   reg_rd   when in_ready='0' else
                   (St_rd'range => '-');
      Rd_Code   <= Code     when in_ready='1' else
                   reg_Code when in_ready='0' else
                   none;
      Rd_PC     <= S_PC     when in_ready='1' else
                   reg_PC   when in_ready='0' else
                   (St_PC'range => '-');
      Rd_ThNo   <= S_ThNo   when in_ready='1' else
                   reg_ThNo when in_ready='0' else
                   (St_ThNo'range => '-');
      RSy_Ready <= in_ready;
    end generate;
    NRS:if not With_Ready_Sync generate
      Ld_DataSync: process(CLK)
        variable Valid : std_logic := '0';
      begin
        if rising_edge(CLK) then
          if RESET='1' then
            Valid       := '0';
          elsif RSy_Ready='1' then
            Valid       := RSy_Valid;
            Rd_rd       <= S_rd;
            Rd_Code     <= Code;
            Rd_PC       <= S_PC;
            Rd_ThNo     <= S_ThNo;
          end if;
          Rd_Valid    <= Valid;
        end if;
      end process;
      RSy_Ready <= (not Rd_Valid) or Rd_Ready;
    end generate;
  end block;
 
  DS_Merge: process(Rd_Valid, Rd_rd, Rd_Code, Rd_PC, Rd_ThNo, SR_Valid, SR_DAT, Ld_Ready)
  begin
    Rd_Ready    <= '0';
    SR_Ready    <= '0';
    Ld_Valid    <= '0';
    Ld_rd       <= Rd_rd;
    Ld_Code     <= Rd_Code;
    Ld_PC       <= Rd_PC;
    Ld_ThNo     <= Rd_ThNo;
    Ld_DAT      <= SR_DAT;
    if (Rd_Valid='1') and (SR_Valid='1') then
      Ld_Valid    <= '1';
      Rd_Ready    <= Ld_Ready;
      SR_Ready    <= Ld_Ready;
    end if;
  end process;
  
  OutAlign: process(Ld_DAT,Ld_Code)
    constant Zeros : std_logic_vector(31 downto 0) := (others => '0');
  begin
    case(Ld_Code) is
      when W    => Ld_rdV <= Ld_DAT;
      when H_2  => Ld_rdV <= (1 to 16 => Ld_DAT(15)) & Ld_DAT(31 downto 16);
      when H_0  => Ld_rdV <= (1 to 16 => Ld_DAT(15)) & Ld_DAT(15 downto  0);
      when B_3  => Ld_rdV <= (1 to 24 => Ld_DAT( 7)) & Ld_DAT(31 downto 24);
      when B_2  => Ld_rdV <= (1 to 24 => Ld_DAT( 7)) & Ld_DAT(23 downto 16);
      when B_1  => Ld_rdV <= (1 to 24 => Ld_DAT( 7)) & Ld_DAT(15 downto  8);
      when B_0  => Ld_rdV <= (1 to 24 => Ld_DAT( 7)) & Ld_DAT( 7 downto  0);
      when HU_2 => Ld_rdV <= Zeros(31 downto 16) & Ld_DAT(31 downto 16);
      when HU_0 => Ld_rdV <= Zeros(31 downto 16) & Ld_DAT(15 downto  0);
      when BU_3 => Ld_rdV <= Zeros(31 downto  8) & Ld_DAT(31 downto 24);
      when BU_2 => Ld_rdV <= Zeros(31 downto  8) & Ld_DAT(23 downto 16);
      when BU_1 => Ld_rdV <= Zeros(31 downto  8) & Ld_DAT(15 downto  8);
      when BU_0 => Ld_rdV <= Zeros(31 downto  8) & Ld_DAT( 7 downto  0);
      when none => Ld_rdV <= Zeros;
    end case;
  end process;
  
  DS_MUX: block
    type MuxStates is (MUX0, MUX1, Error);
    signal state      : MuxStates;
    signal next_state : MuxStates;
    signal MuxSel     : std_logic;
  begin
  
    process(state, RESET, M_Ready, Ld_Valid, St_Valid)
    begin
      next_state <= Error;
      M_Valid    <= '0';
      Ld_Ready   <= '0';
      St_Ready   <= '0';
      MuxSel     <= '-';
      if RESET='1' then
        next_state <= MUX0;
      elsif RESET/='0' then
        next_state <= error;
      else
        case state is
          when MUX0  =>
            if (Ld_Valid='0') and (St_Valid='1') and (M_Ready='1') then
              next_state <= MUX0;
              MuxSel     <= '1';
              M_Valid    <= '1';
              St_Ready   <= '1';
            elsif (Ld_Valid='1') and (M_Ready='1') then
              next_state <= MUX1;
              MuxSel     <= '0';
              M_Valid    <= '1';
              Ld_Ready   <= '1';
            elsif (Ld_Valid='0') and (St_Valid='1') and (M_Ready='0') then
              next_state <= MUX1;
              M_Valid    <= '1';
              MuxSel     <= '1';
            elsif (Ld_Valid='1') and (M_Ready='0') then
              next_state <= MUX0;
              M_Valid    <= '1';
              MuxSel     <= '0';
            elsif (Ld_Valid='0') and (St_Valid='0') then
              next_state <= MUX0;
            end if;
          when MUX1  =>
            if (Ld_Valid='1') and (St_Valid='0') and (M_Ready='1') then
              next_state <= MUX1;
              MuxSel     <= '0';
              M_Valid    <= '1';
              Ld_Ready   <= '1';
            elsif (St_Valid='1') and (M_Ready='1') then
              next_state <= MUX0;
              MuxSel     <= '1';
              M_Valid    <= '1';
              St_Ready   <= '1';
            elsif (Ld_Valid='1') and (St_Valid='0') and (M_Ready='0') then
              next_state <= MUX0;
              M_Valid    <= '1';
              MuxSel     <= '0';
            elsif (St_Valid='1') and (M_Ready='0') then
              next_state <= MUX1;
              M_Valid    <= '1';
              MuxSel     <= '1';
            elsif (Ld_Valid='0') and (St_Valid='0') then
              next_state <= MUX1;
            end if;
          when Error =>
            null;
        end case;
      end if;
    end process;
    
    process(CLK)
    begin
      if rising_edge(CLK) then
        state <= next_state;
      end if;
    end process;
    
    process(MuxSel, Ld_rdV, Ld_rd, Ld_PC, Ld_ThNo, St_rd, St_rdV, St_PC, St_ThNo)
    begin
      if MuxSel='0' then
        M_rdV      <= Ld_rdV;
        M_rd       <= Ld_rd;
        M_PC       <= Ld_PC;
        M_ThNo     <= Ld_ThNo;
      elsif MuxSel='1' then
        M_rdV      <= St_rdV;
        M_rd       <= St_rd;
        M_PC       <= St_PC;
        M_ThNo     <= St_ThNo;
      elsif MuxSel='-' then
        M_rdV      <= (M_rdV'range => '-');
        M_rd       <= (M_rd'range => '-');
        M_PC       <= (M_PC'range => '-');
        M_ThNo     <= (M_ThNo'range => '-');
      else
        M_rdV      <= (M_rdV'range => 'X');
        M_rd       <= (M_rd'range => 'X');
        M_PC       <= (M_PC'range => 'X');
        M_ThNo     <= (M_ThNo'range => 'X');
      end if;
    end process;
    
  end block;

end arch;