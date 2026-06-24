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
-- Error Fifo
-- The fifo buffers thread tokens plus ErrID to avoid blocking in the data flow
-- The depth of the the fifo is 2**M, this value should correspond with
-- the number of possible threads in the processor.
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity ErrorFifo is
  generic (
    M               : integer :=  3;
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  3;
    ERR_ID_WIDTH    : integer :=  2
  );
  port (
    CLK     : in  std_logic;
    RESET   : in  std_logic;
    -- Write
    S_Valid : in  std_logic;
    S_Ready : out std_logic;
    S_PC    : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo  : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_ErrID : in  std_logic_vector(ERR_ID_WIDTH-1 downto 0);
    -- Read
    M_Valid : out std_logic;
    M_Ready : in  std_logic;
    M_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_ErrID : out std_logic_vector(ERR_ID_WIDTH-1 downto 0)
  );
end ErrorFifo;

library ieee;
use ieee.numeric_std.all;
architecture arch of ErrorFifo is
  signal M_Counter : unsigned(M-1 downto 0);
  signal Empty     : std_logic;
  signal Full      : std_logic;
  --
  type PC_Memory is array(0 to 2**M-1) of std_logic_vector(ADR_WIDTH-1 downto 0);
  signal PC_Fifo : PC_Memory := (others => (ADR_WIDTH-1 downto 0 => '-'));
  --
  type ThNo_Memory is array(0 to 2**M-1) of std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal ThNo_Fifo : ThNo_Memory:= (others => (THREAD_NO_WIDTH-1 downto 0 => '-'));
  --
  type ErrID_Memory is array(0 to 2**M-1) of std_logic_vector(ERR_ID_WIDTH-1 downto 0);
  signal ErrID_Fifo : ErrID_Memory:= (others => (ERR_ID_WIDTH-1 downto 0 => '-'));
begin

  Counters: process (CLK)
    variable S_VCounter : unsigned(M-1 downto 0) := (others => '0');
    variable M_VCounter : unsigned(M-1 downto 0) := (others => '0');
    variable A_VCounter : unsigned(M   downto 0) := (others => '0');
  begin
    if rising_edge(CLK) then
      --
      if RESET='1' then
        S_VCounter := (others => '0');
        M_VCounter := (others => '0');
        A_VCounter := (others => '0');
      elsif RESET='0' then
        if (S_Valid='1') and (Full='0') then
          PC_Fifo(to_integer(S_VCounter))    <= S_PC;
          ThNo_Fifo(to_integer(S_VCounter))  <= S_ThNo;
          ErrID_Fifo(to_integer(S_VCounter)) <= S_ErrID;
          S_VCounter := S_VCounter+1;
          A_VCounter := A_VCounter+1;
        end if;
        if (M_Ready='1') and (Empty='0') then
          M_VCounter := M_VCounter+1;
          A_VCounter := A_VCounter-1;
        end if;
      end if;
      M_Counter <= M_VCounter;
      if A_VCounter=0      then Empty <='1'; M_Valid <= '0'; else Empty <='0'; M_Valid <= '1'; end if;
      if A_VCounter(M)='1' then Full  <='1'; S_Ready <= '0'; else Full  <='0'; S_Ready <= '1'; end if;
      -- DataSync
    end if;
  end Process;

  M_PC    <= PC_Fifo(to_integer(M_Counter));
  M_ThNo  <= ThNo_Fifo(to_integer(M_Counter));
  M_ErrID <= ErrID_Fifo(to_integer(M_Counter));
  
end arch;
