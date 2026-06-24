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
-- StoreResultMUX
-- This pipeline stage multiplexes different computation paths to the
-- final register write block 
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity StoreResultMUX is
  generic (
    INST_ADDR_WIDTH : integer := 32;
    DATA_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  3
  );
  port (
    CLK      : in  std_logic;
    RESET    : in  std_logic;
    -- Input 0
    S0_Valid : in  std_logic;
    S0_Ready : out std_logic;
    S0_PC    : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S0_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S0_rdV   : in  std_logic_vector(31 downto 0);
    S0_rd    : in  std_logic_vector( 4 downto 0);
    -- Input 1
    S1_Valid : in  std_logic;
    S1_Ready : out std_logic;
    S1_PC    : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S1_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S1_rdV   : in  std_logic_vector(31 downto 0);
    S1_rd    : in  std_logic_vector( 4 downto 0);
    -- Input 2
    S2_Valid : in  std_logic;
    S2_Ready : out std_logic;
    S2_PC    : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S2_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S2_rdV   : in  std_logic_vector(31 downto 0);
    S2_rd    : in  std_logic_vector( 4 downto 0);
    -- Output to store result
    M_Valid  : out std_logic;
    M_Ready  : in  std_logic;
    M_PC     : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_rdV    : out std_logic_vector(31 downto 0);
    M_rd     : out std_logic_vector( 4 downto 0)
  );
end StoreResultMUX;

library ieee;
use ieee.numeric_std.all;
architecture arch of StoreResultMUX is
  type MuxSelT is (S0, S1, S2, none, error);
  signal MuxSel : MuxSelT := none;
begin

  -- PC MUX
  M_PC <= S0_PC when MuxSel=S0 else
          S1_PC when MuxSel=S1 else
          S2_PC when MuxSel=S2 else
          (M_PC'range => '-');
  -- ThNo MUX
  M_ThNo <= S0_ThNo when MuxSel=S0 else
            S1_ThNo when MuxSel=S1 else
            S2_ThNo when MuxSel=S2 else
            (M_ThNo'range => '-');
  -- rdV MUX
  M_rdV <= S0_rdV when MuxSel=S0 else
           S1_rdV when MuxSel=S1 else
           S2_rdV when MuxSel=S2 else
           (M_rdV'range => '-');
  -- rd MUX
  M_rd  <= S0_rd  when MuxSel=S0 else
           S1_rd  when MuxSel=S1 else
           S2_rd  when MuxSel=S2 else
           (M_rd'range => '-');

  FSM: block
    type States is (MUX, Wait0, Wait1, Wait2, error);
    signal State      : States;
    signal NextState  : States;
  begin
    process (State, RESET, S0_Valid, S1_Valid, S2_Valid, M_Ready)
    begin
      NextState  <= error;
      S0_Ready <= '0';
      S1_Ready <= '0';
      S2_Ready <= '0';
      MuxSel   <= none;
      M_Valid  <= '0';
      if RESET='1' then
        NextState  <= MUX;
      elsif RESET='0' then
        case State is
          when MUX =>
            if (S0_Valid='0') and (S1_Valid='0') and (S2_Valid='0') then
              NextState <= MUX;
            elsif (S0_Valid='1') and (M_Ready='0') then
              NextState <= Wait0;
              M_Valid   <= '1';
              MuxSel    <= S0;
            elsif (S0_Valid='1') and (M_Ready='1') then
              NextState <= MUX;
              M_Valid   <= '1';
              MuxSel    <= S0;
              S0_Ready  <= '1';
            elsif (S0_Valid='0') and (S1_Valid='1') and (M_Ready='0') then
              NextState <= Wait1;
              M_Valid   <= '1';
              MuxSel    <= S1;
            elsif (S0_Valid='0') and (S1_Valid='1') and (M_Ready='1') then
              NextState <= MUX;
              M_Valid   <= '1';
              MuxSel    <= S1;
              S1_Ready  <= '1';
            elsif (S0_Valid='0') and (S1_Valid='0') and (S2_Valid='1') and (M_Ready='0') then
              NextState <= Wait2;
              M_Valid   <= '1';
              MuxSel    <= S2;
            elsif (S0_Valid='0') and (S1_Valid='0') and (S2_Valid='1') and (M_Ready='1') then
              NextState <= MUX;
              M_Valid   <= '1';
              MuxSel    <= S2;
              S2_Ready  <= '1';
            end if;
          when Wait0 =>
            if (S0_Valid='1') and (M_Ready='0') then
              NextState <= Wait0;
              M_Valid   <= '1';
              MuxSel    <= S0;
            elsif (S0_Valid='1') and (M_Ready='1') then
              NextState <= MUX;
              M_Valid   <= '1';
              MuxSel    <= S0;
              S0_Ready  <= '1';
            end if;
          when Wait1 =>
            if (S1_Valid='1') and (M_Ready='0') then
              NextState <= Wait1;
              M_Valid   <= '1';
              MuxSel    <= S1;
            elsif (S1_Valid='1') and (M_Ready='1') then
              NextState <= MUX;
              M_Valid   <= '1';
              MuxSel    <= S1;
              S1_Ready  <= '1';
            end if;
          when Wait2 =>
            if (S2_Valid='1') and (M_Ready='0') then
              NextState <= Wait2;
              M_Valid   <= '1';
              MuxSel    <= S2;
            elsif (S2_Valid='1') and (M_Ready='1') then
              NextState <= MUX;
              M_Valid   <= '1';
              MuxSel    <= S2;
              S2_Ready  <= '1';
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
  
end arch;
