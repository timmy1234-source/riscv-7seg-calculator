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
-- Wishbone Bridge
-- Read and write accesses are bridged to wishbone bus. The wishbone bus is extended
-- by the ThNo signal, which supplements the ADR signal.
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity WB_Bridge is
  generic (
    ADR_WIDTH       : integer := 14;   -- Number of address bits
    THREAD_NO_WIDTH : integer :=  5;   -- Number of ThNo bits
    SR_ReadySync    : boolean := true; -- Place ReadySync at SR_ input stream
    SR_DataSync     : boolean := true; -- Place DataSync at SR_ input stream
    MR_ReadySync    : boolean := true; -- Place ReadySync at MR_ output stream
    MR_DataSync     : boolean := true  -- Place DataSync at MR_ output stream
  );
  port (
    CLK      : in  std_logic;
    RESET    : in  std_logic;
    -- AxiS Write Request
    SW_Valid : in  std_logic;
    SW_Ready : out std_logic;
    SW_ADR   : in  std_logic_vector(ADR_WIDTH-1 downto 2);
    SW_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    SW_SEL   : in  std_logic_vector( 3 downto 0);
    SW_DAT   : in  std_logic_vector(31 downto 0);
    -- AxiS Read Request
    SR_Valid : in  std_logic;
    SR_Ready : out std_logic;
    SR_ADR   : in  std_logic_vector(ADR_WIDTH-1 downto 2);
    SR_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- AxiS Read Response
    MR_Valid : out std_logic;
    MR_Ready : in  std_logic;
    MR_DAT   : out std_logic_vector(31 downto 0);
    -- Wishbone Bus
    WB_STB   : out std_logic;
    WB_WE    : out std_logic;
    WB_SEL   : out std_logic_vector( 3 downto 0);
    WB_ADR   : out std_logic_vector(ADR_WIDTH-1 downto 2);
    WB_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    WB_MOSI  : out std_logic_vector(31 downto 0);
    WB_MISO  : in  std_logic_vector(31 downto 0);
    WB_ACK   : in  std_logic
  );
end WB_Bridge;

library ieee;
use ieee.numeric_std.all;
architecture arch of WB_Bridge is
  signal WB_RValid : std_logic;
  signal WB_WE_i   : std_logic;
  signal tmp       : std_logic_vector(31 downto 0);
  signal S1_Valid : std_logic;
  signal S1_Ready : std_logic;
  signal S1_ADR   : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal S1_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal M1_Valid : std_logic;
  signal M1_Ready : std_logic;
  signal M1_DAT   : std_logic_vector(31 downto 0);
begin

  Sync_SR: block
    signal S0_Valid : std_logic;
    signal S0_Ready : std_logic;
    signal S0_ADR   : std_logic_vector(ADR_WIDTH-1 downto 2);
    signal S0_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  begin
  
    -- NoReadySync from SR_ to S0_
    NoReadySync_WBB: if not SR_ReadySync generate
       S0_Valid <= SR_Valid;
       SR_Ready <= S0_Ready;
       S0_ADR   <= SR_ADR;
       S0_ThNo  <= SR_ThNo;
    end generate;

    -- ReadySync from SR_ to S0_
    ReadySync_WBB: if SR_ReadySync generate
      signal tmp_Valid : std_logic;
      signal tmp_Ready : std_logic;
      signal tmp_ADR   : std_logic_vector(ADR_WIDTH-1 downto 2);
      signal tmp_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
      signal SR_iReady : std_logic;
    begin
      process(CLK)
      begin
        if rising_edge(CLK) then
          if RESET='1' then
            tmp_Valid   <= '0';
            tmp_ADR    <= (tmp_ADR'range  => '-');
            tmp_ThNo   <= (tmp_ThNo'range => '-');
            SR_iReady <= '0';
          else
            SR_iReady <= (not S0_Valid) or S0_Ready; 
            if SR_iReady='1' then
              tmp_Valid <= SR_Valid;
              tmp_ADR   <= SR_ADR;
              tmp_ThNo  <= SR_ThNo;
            end if;
          end if;
        end if;
      end process;
      S0_Valid <= SR_Valid when SR_iReady='1' else tmp_Valid when SR_iReady='0' else 'X';
      S0_ADR   <= SR_ADR   when SR_iReady='1' else tmp_ADR   when SR_iReady='0' else (SR_ADR'range  => 'X');
      S0_ThNo  <= SR_ThNo  when SR_iReady='1' else tmp_ThNo  when SR_iReady='0' else (SR_ThNo'range => 'X');
      SR_Ready <= SR_iReady;
    end generate;

    -- DataSync from S0_ to S1_
    DataSync_WBB: if SR_DataSync generate
    begin
      process(CLK)
      begin
        if rising_edge(CLK) then
          if RESET='1' then
            S1_Valid <= '0';
            S1_ADR   <= (S0_ADR'range => '-');
            S1_ThNo  <= (S0_ThNo'range => '-');
          elsif S0_Ready='1' then
            S1_Valid <= S0_Valid;
            S1_ADR   <= S0_ADR;
            S1_ThNo  <= S0_ThNo;
          end if;
        end if;
      end process;
      S0_Ready <= (not S1_Valid) or S1_Ready;
    end generate;

    NoSync_WBB: if not SR_DataSync generate
    begin
      S1_Valid  <= S0_Valid;
      S0_Ready  <= S1_Ready;
      S1_ADR    <= S0_ADR;
      S1_ThNo   <= S0_ThNo;
    end generate;
    
  end block;

  Sync_MR: block
    signal M0_Valid : std_logic;
    signal M0_Ready : std_logic;
    signal M0_DAT   : std_logic_vector(31 downto 0);
  begin
  
    -- NoReadySync from M1_ to M0_
    NoReadySync_WBB: if not MR_ReadySync generate
       M0_Valid <= M1_Valid;
       M1_Ready <= M0_Ready;
       M0_DAT   <= M1_DAT;
    end generate;

    -- ReadySync from M1_ to M0_
    ReadySync_WBB: if MR_ReadySync generate
      signal tmp_Valid : std_logic;
      signal tmp_Ready : std_logic;
      signal tmp_DAT   : std_logic_vector(31 downto 0);
      signal M1_iReady : std_logic;
    begin
      process(CLK)
      begin
        if rising_edge(CLK) then
          if RESET='1' then
            tmp_Valid  <= '0';
            tmp_DAT    <= (tmp_DAT'range  => '-');
            M1_iReady <= '0';
          else
            M1_iReady <= (not M0_Valid) or M0_Ready; 
            if M1_iReady='1' then
              tmp_Valid <= M1_Valid;
              tmp_DAT   <= M1_DAT;
            end if;
          end if;
        end if;
      end process;
      M0_Valid <= M1_Valid when M1_iReady='1' else tmp_Valid when M1_iReady='0' else 'X';
      M0_DAT   <= M1_DAT   when M1_iReady='1' else tmp_DAT   when M1_iReady='0' else (M1_DAT'range  => 'X');
      M1_Ready <= M1_iReady;
    end generate;

    -- DataSync from M0_ to MR_
    DataSync_WBB: if MR_DataSync generate
      signal MR_iValid : std_logic;
    begin
      process(CLK)
      begin
        if rising_edge(CLK) then
          if RESET='1' then
            MR_iValid <= '0';
            MR_DAT   <= (M0_DAT'range => '-');
          elsif M0_Ready='1' then
            MR_iValid <= M0_Valid;
            MR_DAT   <= M0_DAT;
          end if;
        end if;
      end process;
      M0_Ready <= (not MR_iValid) or MR_Ready;
      MR_Valid  <= MR_iValid;
    end generate;

    NoSync_WBB: if not MR_DataSync generate
    begin
      MR_Valid  <= M0_Valid;
      M0_Ready  <= MR_Ready;
      MR_DAT    <= M0_DAT;
    end generate;
    
  end block;

  WB_SEL  <= SW_SEL;
  WB_MOSI <= SW_DAT;
  WB_WE   <= WB_WE_i;
  WB_ADR  <= S1_ADR when WB_WE_i='0' else
             SW_ADR when WB_WE_i='1' else
             (WB_ADR'range => 'X');
  WB_ThNo <= S1_ThNo when WB_WE_i='0' else
             SW_ThNo when WB_WE_i='1' else
             (WB_ThNo'range => 'X');
  M1_DAT  <= WB_MISO when WB_RValid='1' else
             tmp     when WB_RValid='0' else
             (M1_DAT'range => 'X');
  
  Reg: process(CLK)
  begin
    if rising_edge(CLK) then
      if RESET='1' then
        tmp <= (tmp'range => '0');
      elsif WB_RValid='1' then
        tmp <= WB_MISO;
      end if;
    end if;
  end process;
  
  FSM: block
    type States is (ReadWrite, WB_Wait, M1_Wait, XXX);
    signal State : States;
    signal NextState : States;
  begin
    
    Next_and_Mealy: process(State, RESET, M1_Ready, S1_Valid, SW_Valid, WB_ACK)
    begin
      NextState <= XXX;
      M1_Valid  <= '0';
      S1_Ready  <= '0';
      SW_Ready  <= '0';
      WB_RValid <= '0';
      WB_WE_i   <= '0';
      WB_STB    <= '0';
      if RESET='1' then
        NextState <= ReadWrite;
      elsif RESET='0' then
        case State is
          when ReadWrite =>
            if (S1_valid='0') and (SW_valid='0') then
              NextState <= ReadWrite;
            elsif SW_valid='1' then
              NextState <= ReadWrite;
              WB_STB  <= '1';
              WB_WE_i <= '1';
              if WB_ACK='1' then
                SW_Ready <= '1';
              end if;
            elsif (S1_valid='1') and (SW_valid='0') then
              WB_STB <= '1';
              if WB_ACK='0' then
                NextState <= WB_Wait;
              elsif (WB_ACK='1') then
                WB_RValid <='1';
                M1_Valid  <='1';
                if (M1_Ready='0') then
                  NextState <= M1_Wait;
                elsif (M1_Ready='1') then
                  NextState <= ReadWrite;
                  S1_Ready  <= '1';
                end if;
              end if;
            end if;
          when WB_Wait =>
            WB_STB <= '1';
            if WB_ACK='0' then
              NextState <= WB_Wait;
            elsif (WB_ACK='1') then
              WB_RValid <='1';
              M1_Valid  <='1';
              if (M1_Ready='0') then
                NextState <= M1_Wait;
              elsif (M1_Ready='1') then
                NextState <= ReadWrite;
                S1_Ready  <= '1';
              end if;
            end if;
          when M1_Wait =>
            M1_Valid <= '1';
            if (M1_Ready='0') then
              NextState <= M1_Wait;
            elsif (M1_Ready='1') then
              NextState <= ReadWrite;
              S1_Ready <= '1';
            end if;
          when XXX =>
            M1_Valid  <= 'X';
            S1_Ready  <= 'X';
            SW_Ready  <= 'X';
            WB_RValid <= 'X';
            WB_WE_i   <= 'X';
            WB_STB    <= 'X';
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

end arch;

