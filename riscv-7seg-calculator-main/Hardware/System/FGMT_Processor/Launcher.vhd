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
-- Launcher
-- responsible to launch the first thread.
-- Then it offers infrastructure to launch further threads
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity Launcher is
  generic (
    Start_Valid  : std_logic := '0';
    StartAddress : std_logic_vector;
    StartThread  : std_logic_vector
  );
  port (
    CLK       : in  std_logic;
    RESET     : in  std_logic;
    -- Wishbone bus
    WB_STB    : in  std_logic;
    WB_ADR    : in  std_logic_vector(3 downto 2);
    WB_THNO   : in  std_logic_vector(StartThread'range);
    WB_SEL    : in  std_logic_vector(3 downto 0);
    WB_WE     : in  std_logic;
    WB_MOSI   : in  std_logic_vector(31 downto 0);
    WB_MISO   : out std_logic_vector(31 downto 0);
    WB_ACK    : out std_logic;
    -- Thread output
    Lch_Valid : out std_logic;
    Lch_Ready : in  std_logic;
    Lch_PC    : out std_logic_vector(StartAddress'range);
    Lch_ThNo  : out std_logic_vector(StartThread'range)
  );
end Launcher;

library ieee;
use ieee.numeric_std.all;
architecture arch of Launcher is
  signal Do_Launch    : std_logic;
  signal Wr_PC        : std_logic;
  signal Wr_Own_ThId  : std_logic;
  signal En_Thread    : std_logic;
  signal Thread_Valid : std_logic;
  signal En_ThNo      : std_logic;
  signal ThNo_Valid   : std_logic;
  signal ReadStatus   : std_logic;
  signal occupied     : std_logic;
  signal equal        : std_logic;
  signal Lch_iValid   : std_logic;
  signal Consumed     : std_logic;
  signal Thread       : std_logic_vector(StartThread'range);
  constant Zeros      : std_logic_vector(31 downto 0) := (others => '0');
  constant SEL_STATUS : std_logic_vector(3 downto 2) := "00";
  constant SEL_THREAD : std_logic_vector(3 downto 2) := "01";
  constant SEL_PC     : std_logic_vector(3 downto 2) := "10";
  constant SEL_ThNo   : std_logic_vector(3 downto 2) := "11";
begin

  Decode: process(WB_STB, WB_ADR, WB_SEL, WB_WE)
  begin
    WB_ACK      <= '0';
    ReadStatus  <= '0';
    Wr_Own_ThId <= '0';
    Wr_PC       <= '0';
    Do_Launch   <= '0';
    if WB_STB='1' then
      if WB_WE='0' then
        if    WB_ADR=SEL_STATUS then WB_ACK <= '1'; ReadStatus  <= '1';
        end if;
      elsif WB_WE='1' then
        if    WB_ADR=SEL_THREAD and WB_SEL="1111" then WB_ACK <= '1'; Wr_Own_ThId <= '1';
        elsif WB_ADR=SEL_PC     and WB_SEL="1111" then WB_ACK <= '1'; Wr_PC       <= '1';
        elsif WB_ADR=SEL_ThNo   and WB_SEL="1111" then WB_ACK <= '1'; Do_Launch   <= '1';
        end if;
      end if;
    end if;
  end process;

  En_ThNo   <= (not ThNo_Valid)   or Consumed;
  En_Thread <= (not Thread_Valid) or Consumed;
  Consumed  <= Lch_iValid and Lch_Ready;
  
  process (CLK)
    variable Valid   : std_logic := '0';
    variable PC      : std_logic_vector(StartAddress'range) := (others => '-');
    variable ThNo    : std_logic_vector(StartThread'range ) := (others => '-');
    variable Running : std_logic := '0';
  begin
    if rising_edge(CLK) then
      if RESET='1' then
        -- reset launcher
        Thread_Valid <= '0';
        Valid   := '0';
        PC      := (others => '-');
        ThNo    := (others => '-');
        Running := '0';
      elsif Running='0' then
        -- Launch initial thread
        Thread_Valid <= Start_Valid;
        Valid   := Start_Valid;
        PC      := StartAddress;
        ThNo    := StartThread;
        Running := '1';
      else
        -- write PC register
        if Wr_PC='1' then
          PC    := WB_MOSI(StartAddress'range);
        end if;
        -- Write ThNo DataSync register
        if (Do_Launch='1') and (occupied='1') and (En_ThNo='1') then
          Valid := '1';
          ThNo  := WB_MOSI(StartThread'range);
        elsif ((Do_Launch='0') or (occupied='0')) and (En_ThNo='1') then
          Valid := '0';
          ThNo  := (others => '-');
        end if;
        -- Write own ThNo DataSync register
        if Wr_Own_ThId='1' and En_Thread='1' then
          Thread_Valid <= '1';
          Thread       <= WB_THNO;
        elsif Wr_Own_ThId='0' and En_Thread='1' then
          Thread_Valid <= '0';
          Thread       <= (others => '-');
        end if;
      end if;
      ThNo_Valid <= Valid;
      Lch_PC     <= PC;
      Lch_ThNo   <= ThNo;
    end if;
  end Process;

  Lch_iValid <= Thread_Valid and ThNo_Valid;
  Lch_Valid  <= Lch_iValid;
  
  occupied <= Thread_Valid and equal;
  equal    <= '1' when Thread=WB_THNO else '0';
  
  process (ReadStatus, occupied)
  begin
    WB_MISO <= Zeros;
    if ReadStatus='1'  then WB_MISO(0) <= occupied;
    else                    WB_MISO    <= (others => '-');
    end if;
  end process;

end arch;

