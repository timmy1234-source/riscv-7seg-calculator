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
-- ErrHandling
-- Destination for error tokens
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity ErrHandling is
  generic (
    ADR_WIDTH       : integer := 32;
    THREAD_NO_WIDTH : integer :=  3;
    ERR_ID_WIDTH    : integer :=  2
  );
  port (
    CLK           : in  std_logic;
    RESET         : in  std_logic;
    -- Wishbone bus
    WB_STB        : in  std_logic;
    WB_ADR        : in  std_logic_vector(3 downto 2);
    WB_SEL        : in  std_logic_vector(3 downto 0);
    WB_WE         : in  std_logic;
    WB_MOSI       : in  std_logic_vector(31 downto 0);
    WB_MISO       : out std_logic_vector(31 downto 0);
    WB_ACK        : out std_logic;
    -- Error Token Input
    Err_Valid     : in  std_logic;
    Err_Ready     : out std_logic;
    Err_PC        : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    Err_ThNo      : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    Err_ErrID     : in  std_logic_vector(ERR_ID_WIDTH-1 downto 0);
    -- Interrupt output
    Err_Interrupt : out std_logic
  );
end ErrHandling;

library ieee;
use ieee.numeric_std.all;
architecture arch of ErrHandling is
  constant Zeros    : std_logic_vector(31 downto 0) := (others => '0');
  type Selection is (SEL_Valid, SEL_PC, SEL_ThNo, SEL_ErrID, SEL_none);
  signal SEL        : Selection := SEL_none;
  signal Consume    : std_logic;
  signal Valid      : std_logic;
  signal Err_iReady : std_logic;
  signal PC         : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal ThNo       : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal ErrID      : std_logic_vector(ERR_ID_WIDTH-1 downto 0);
begin

  Decode: process(WB_STB, WB_ADR, WB_SEL, WB_WE)
  begin
    SEL     <= SEL_none;
    WB_ACK  <= '0';
    Consume <= '0';
    if WB_STB='1' then
      if WB_WE='0' then
        case WB_ADR is
          when "00" => WB_ACK <= '1'; SEL <= SEL_Valid;
          when "01" => WB_ACK <= '1'; SEL <= SEL_PC;
          when "10" => WB_ACK <= '1'; SEL <= SEL_ThNo;
          when "11" => WB_ACK <= '1'; SEL <= SEL_ErrID;
          when others => null;
        end case;
      elsif (WB_WE='1') and (WB_SEL="1111") and (WB_ADR="10") then
        WB_ACK  <= '1';
        Consume <= '1';
      end if;
    end if;
  end process;
  
  process(SEL, Valid, PC, ThNo, ErrID)
  begin
    WB_MISO <= Zeros;
    case SEL is
      when SEL_Valid =>  WB_MISO(0) <= Valid;
      when SEL_PC    =>  WB_MISO(PC'range)    <= PC;
      when SEL_ThNo  =>  WB_MISO(ThNo'range)  <= ThNo;
      when SEL_ErrID =>  WB_MISO(ErrID'range) <= ErrID;
      when SEL_none  =>  WB_MISO <= (others => '-');
    end case;
  end process;

  Err_iReady <= (not Valid) or Consume;
  Err_Ready  <= Err_iReady;
  
  process (CLK)
  begin
    if rising_edge(CLK) then
      if Err_iReady='1' then
        Valid <= Err_Valid;
        PC    <= Err_PC;
        ThNo  <= Err_ThNo;
        ErrID <= Err_ErrID;
      end if;
    end if;
  end Process;
  
  Err_Interrupt <= Valid;
  
end arch;

