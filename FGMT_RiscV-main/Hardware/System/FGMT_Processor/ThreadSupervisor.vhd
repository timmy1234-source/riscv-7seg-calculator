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
-- ThreadSupervisor
-- Monitor which treads are active
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;
entity ThreadSupervisor is
  generic (
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  5;
    TIME_OUT        : integer := 15
  );
  port (
    CLK            : in  std_logic;
    RESET          : in  std_logic;
    KillThreads    : in  std_logic;
    -- Wishbone bus
    WB_STB         : in  std_logic;
    WB_ADR         : in  std_logic_vector(3 downto 2);
    WB_THNO        : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    WB_SEL         : in  std_logic_vector(3 downto 0);
    WB_WE          : in  std_logic;
    WB_MOSI        : in  std_logic_vector(31 downto 0);
    WB_MISO        : out std_logic_vector(31 downto 0);
    WB_ACK         : out std_logic;
    -- Stream Input
    S_Valid        : in  std_logic;
    S_Ready        : out std_logic;
    S_PC           : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo         : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Stream Output
    M_Valid        : out std_logic;
    M_Ready        : in  std_logic;
    M_PC           : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo         : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Thread Activity Output
    ThreadActivity : out std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    ActiveThreads  : out std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0)
  );
  constant TIME_OUT_Bits : natural := integer(ceil(log2(real(TIME_OUT))));
end ThreadSupervisor;

library ieee;
use ieee.numeric_std.all;
architecture arch of ThreadSupervisor is
  signal ReadThAct : std_logic;
  signal ReadActTh : std_logic;
  signal ReadThNo  : std_logic;
  constant Zeros   : std_logic_vector(31 downto 0) := (others => '0');
  --
  signal SelActThread : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
  signal Terminate    : std_logic;
  signal ThAct        : std_logic;
  signal Remove       : std_logic;
  signal ThActivity   : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
  signal ActiveTh     : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
begin

  Decode: process(WB_STB, WB_ADR, WB_WE)
  begin
    WB_ACK      <= '0';
    ReadThAct   <= '0';
    ReadActTh   <= '0';
    ReadThNo    <= '0';
    if WB_STB='1' then
      if WB_WE='0' then
        if    WB_ADR="00" then WB_ACK <= '1'; ReadActTh <= '1';
        elsif WB_ADR="01" then WB_ACK <= '1'; ReadThAct <= '1';
        elsif WB_ADR="10" then WB_ACK <= '1'; ReadThNo  <= '1';
        end if;
      end if;
    end if;
  end process;
  
  process(ReadThAct, ThActivity, ReadActTh, ActiveTh, ReadThNo, WB_THNO)
  begin
    WB_MISO <= Zeros;
    if    ReadActTh='1' then WB_MISO(ActiveTh'range)   <= ActiveTh;
    elsif ReadThAct='1' then WB_MISO(ThActivity'range) <= ThActivity;
    elsif ReadThNo='1'  then WB_MISO(WB_THNO'range)    <= WB_THNO;
    end if;
  end process;

  -- 1 of N Decoder
  process (S_Valid, S_ThNo)
  begin
    SelActThread <= (SelActThread'range => '0');
    SelActThread(to_integer(unsigned(S_ThNo))) <= S_Valid;
  end process;
  
  -- check if PC points to highest address
  process (S_PC)
    variable AllOnes : std_logic;
  begin
    AllOnes := '1';
    for i in ADR_WIDTH-1 downto 2 loop
      if S_PC(i)='0' then
         AllOnes := '0';
        exit;
      end if;
    end loop;
    Terminate <= AllOnes;
  end process;  

  -- Timeout Register
  TimeOut_regs: for i in SelActThread'range generate  
    inst: process(CLK)
      -- Einen Zaehler fuer jeden Thread einrichten
      variable cnt: unsigned(TIME_OUT_Bits-1 downto 0) := (others=>'0');
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          cnt := to_unsigned(0,TIME_OUT_Bits);
          ThActivity(i) <= '0';
        elsif (i>0) and KillThreads='1' then
          cnt := (others=>'0');
        elsif SelActThread(i)='1' then
          cnt := to_unsigned(TIME_OUT,TIME_OUT_Bits);
        elsif cnt>0 then
          cnt := cnt-1;
        end if;
        if cnt=0 then ThActivity(i) <= '0';
        else          ThActivity(i) <= '1';
        end if;
      end if;
    end process;
  end generate;

  -- Activity Register
  Activity_regs: for i in SelActThread'range generate  
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          ActiveTh(i) <= '0';
        elsif (i>0) and KillThreads='1' then
          ActiveTh(i) <= '0';
        elsif SelActThread(i)='1' then
          ActiveTh(i) <= ThAct;
        end if;
      end if;
    end process;
  end generate;

  ThAct   <= not Terminate;
  M_Valid <= (not Remove) and S_Valid;
  S_Ready <= Remove or M_Ready;
  M_PC    <= S_PC;
  M_ThNo  <= S_ThNo;
  Remove  <= '1' when (Terminate='1') or (KillThreads='1' and SelActThread(0)='0') else '0';
  
  ThreadActivity <= ThActivity;
  ActiveThreads  <= ActiveTh;
  
end arch;