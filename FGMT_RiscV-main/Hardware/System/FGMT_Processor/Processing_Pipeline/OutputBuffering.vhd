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
-- OutputBuffering
-- Variable stage that can be switched between DataSync, ReadySync and none
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
--use work.FGMT_pack.all;
entity OutputBuffering is
  generic (
    SyncOnOutput : integer := 1; -- 0:none, 1:DataSync, 2:ReadySync,  3:ReadySync and DataSync
    DATA_WIDTH   : integer := 32
  );
  port (
    CLK     : in  std_logic;
    RESET   : in  std_logic;
    -- Input
    S_Valid : in  std_logic;
    S_Ready : out std_logic;
    S_Data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    -- Output
    M_Valid : out std_logic;
    M_Ready : in  std_logic;
    M_Data  : out std_logic_vector(DATA_WIDTH-1 downto 0)
  );
end OutputBuffering;

architecture arch of OutputBuffering is
begin
  WithDataSync: if SyncOnOutput=1 generate -- DataSync
    signal S_Ready_i : std_logic;
    signal M_Valid_i : std_logic;
  begin
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          M_Valid_i  <= '0';
          M_Data     <= (M_Data'range => '-'); 
        elsif S_Ready_i='1' then
          M_Valid_i  <= S_Valid;
          M_Data     <= S_Data; 
        end if;
      end if;
    end process;
    S_Ready_i <= (not M_Valid_i) or M_Ready;
    S_Ready   <= S_Ready_i;
    M_Valid   <= M_Valid_i;
  end generate;
  --
  WithReadySync: if SyncOnOutput=2 generate --ReadySync
    signal S_Ready_i : std_logic;
    signal M_Valid_i : std_logic;
    signal tmp_Valid : std_logic :='0';
    signal tmp_Data  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '-');
  begin
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          tmp_Valid  <= '0';
          tmp_Data   <= (M_Data'range => '-');
          S_Ready_i  <= '0';
        else
          S_Ready_i <= (not M_Valid_i) or M_Ready; 
          if S_Ready_i='1' then
            tmp_Valid <= S_Valid;
            tmp_Data  <= S_DATA;
          end if;
        end if;
      end if;
    end process;
    M_Valid_i <= S_Valid when S_Ready_i='1' else tmp_Valid when S_Ready_i='0' else 'X';
    M_Data    <= S_Data  when S_Ready_i='1' else tmp_Data  when S_Ready_i='0' else (M_DATA'range => 'X');
    S_Ready   <= S_Ready_i;
    M_Valid   <= M_Valid_i;
  end generate;
  --
  WithDataAndReadySync: if SyncOnOutput=3 generate --DataSync and ReadySync
    signal S_Ready_i : std_logic;
    signal M_Valid_i : std_logic;
    signal tmp_Valid : std_logic :='0';
    signal tmp_Data  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '-');
    signal I_Valid   : std_logic :='0';
    signal I_Data    : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '-');
    signal I_Ready   : std_logic;
  begin
    -- First a ReadySync form S_ to I_
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          tmp_Valid  <= '0';
          tmp_Data   <= (S_Data'range => '-');
          S_Ready_i  <= '0';
        else
          S_Ready_i <= (not I_Valid) or I_Ready; 
          if S_Ready_i='1' then
            tmp_Valid <= S_Valid;
            tmp_Data  <= S_DATA;
          end if;
        end if;
      end if;
    end process;
    I_Valid <= S_Valid when S_Ready_i='1' else tmp_Valid when S_Ready_i='0' else 'X';
    I_Data  <= S_Data  when S_Ready_i='1' else tmp_Data  when S_Ready_i='0' else (I_DATA'range => 'X');
    S_Ready <= S_Ready_i;
    -- Then a DataSync form I_ to M_
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          M_Valid_i  <= '0';
          M_Data     <= (M_Data'range => '-'); 
        elsif I_Ready='1' then
          M_Valid_i  <= I_Valid;
          M_Data     <= I_Data; 
        end if;
      end if;
    end process;
    I_Ready <= (not M_Valid_i) or M_Ready;
    M_Valid <= M_Valid_i;

  end generate;
  
  --
  NoDataSync: if SyncOnOutput= 0 generate -- none
    M_Valid <= S_Valid;
    M_Data  <= S_Data;
    S_Ready <= M_Ready;
  end generate;
end arch;
