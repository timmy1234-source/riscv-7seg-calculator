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
-- HardwareBreakpoints
-- Used to debug FGMT-RiscV threads
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
entity HardwareBreakpoints is
  generic (
    ADR_WIDTH       : integer := 13; -- Values in range 32..13
    THREAD_NO_WIDTH : integer :=  3;
    WITH_DATASYNC   : boolean := true
  );
  port(
    CLK       : in  std_logic;
    RESET     : in  std_logic;
    -- Wishbone bus
    WB_STB    : in    std_logic;
    WB_ADR    : in    std_logic_vector(5 downto 2);
    WB_SEL    : in    std_logic_vector(3 downto 0);
    WB_WE     : in    std_logic;
    WB_MOSI   : in    std_logic_vector(31 downto 0);
    WB_MISO   : out   std_logic_vector(31 downto 0);
    WB_ACK    : out   std_logic;
    -- Debug Streaming Input
    S_Valid   : in  std_logic;
    S_Ready   : out std_logic;
    S_PC      : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo    : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Ebreak Streaming Input
    HBK_Valid : out std_logic;
    HBK_Ready : in  std_logic;
    HBK_PC    : out std_logic_vector(ADR_WIDTH-1 downto 0);
    HBK_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Hardware Breakpoint Streaming Input
    M_Valid   : out std_logic;
    M_Ready   : in  std_logic;
    M_PC      : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
  -- Increasing the number of breakpoints requires to widen the WB_ADR bus
  constant NumberOfBreakpoints : natural := 2**WB_ADR'Length - 2;
end HardwareBreakpoints;

library IEEE;
use IEEE.numeric_std.all;
architecture arch of HardwareBreakpoints is
  signal SEL_ID     : std_logic;
  signal SEL_HBKsEn : std_logic;
  signal SEL_HBKs   : std_logic;
  signal HBKsEn     : std_logic_vector(NumberOfBreakpoints-1 downto 0);
  type HBKsType is array (NumberOfBreakpoints-1 downto 0) of std_logic_vector(ADR_WIDTH-1 downto 0);
  signal HBKs       : HBKsType;
  signal IsHBK      : std_logic;
  signal IsHBK0     : std_logic;
  signal S0_Valid   : std_logic;
  signal S0_Ready   : std_logic;
  signal S0_PC      : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal S0_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
begin

  Decode: process(WB_STB, WB_ADR, WB_SEL, WB_WE)
    constant ACK_OK:          std_logic := '1';
    constant ACK_no_Function: std_logic := '1'; -- WB_ACK value when accessing unused memory location
  begin
    SEL_ID     <= '0';
    SEL_HBKsEn <= '0';
    SEL_HBKs   <= '0';
    WB_ACK     <= '0';
    if    (WB_STB='1') and (unsigned(WB_ADR)=0) and (WB_WE='0') then SEL_ID     <= '1';
    elsif (WB_STB='1') and (unsigned(WB_ADR)=1)                 then SEL_HBKsEn <= '1';
    elsif (WB_STB='1') and (unsigned(WB_ADR)>1)                 then SEL_HBKs   <= '1';
    end if;
  end process;

  process(WB_WE, WB_ADR, SEL_ID, SEL_HBKsEn, SEL_HBKs, HBKsEn, HBKs)
  begin
    WB_MISO <= (others => '-');
    if WB_WE='1' then
      if    SEL_ID='1'     then WB_MISO <= x"b1f00000";
      elsif SEL_HBKsEn='1' then WB_MISO(NumberOfBreakpoints-1 downto 0) <= HBKsEn;
      elsif SEL_HBKs='1'   then WB_MISO(S_PC'range) <= HBKs(to_integer(unsigned(WB_ADR))-2);
      end if;
    end if;
  end process;

  process (CLK)
  begin
    if rising_edge(CLK) then
      if    RESET='1' then
        HBKsEn <= (HBKsEn'range => '0');
      elsif  (WB_WE='1') and (WB_SEL="1111") then
        if    SEL_HBKsEn='1' then
          HBKsEn <= WB_MOSI(HBKsEn'range);
        elsif SEL_HBKs='1'   then
          HBKs(to_integer(unsigned(WB_ADR))-2) <= WB_MOSI(ADR_WIDTH-1 downto 0);
        end if;
      end if;
    end if;
  end process;
  
  process(HBKsEn, HBKs, S_PC, S_Valid)
  begin
    IsHBK <= '0';
    for i in 0 to NumberOfBreakpoints-1 loop
      if (HBKsEn(i)='1') and (S_Valid='1') then
        if (HBKs(i)=S_PC) then
          IsHBK <= '1';
          exit;
        end if;
      end if;
    end loop;
  end process;

  PlaceDataSync: if WITH_DATASYNC generate -- DataSync
    signal S_Ready_i : std_logic;
    signal S0_Valid_i : std_logic;
  begin
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          S0_Valid_i <= '0';
          S0_PC      <= (S0_PC'range   => '-'); 
          S0_ThNo    <= (S0_ThNo'range => '-'); 
          IsHBK0     <= '0';
        elsif S_Ready_i='1' then
          S0_Valid_i <= S_Valid;
          S0_PC      <= S_PC;
          S0_ThNo    <= S_ThNo;          
          IsHBK0     <= IsHBK;
        end if;
      end if;
    end process;
    S_Ready_i <= (not S0_Valid_i) or S0_Ready;
    S_Ready   <= S_Ready_i;
    S0_Valid   <= S0_Valid_i;
  end generate;

  noDataSync: if not WITH_DATASYNC generate
  begin
    S0_Valid <= S_Valid;
    S_Ready  <= S0_Ready; 
    S0_PC    <= S_PC;
    S0_ThNo  <= S_ThNo;
  end generate;

  M_PC     <= S0_PC;
  M_ThNo   <= S0_ThNo;  
  HBK_PC   <= S0_PC;
  HBK_ThNo <= S0_ThNo;
  process(S0_Valid, M_Ready, HBK_Ready, IsHBK0)
  begin
    S0_Ready  <= '0';
    M_Valid   <= '0';
    HBK_Valid <= '0';
    if IsHBK0='0' then
      M_Valid <= S0_Valid;
      S0_Ready <= M_Ready;
    elsif IsHBK0='1' then
      HBK_Valid <= S0_Valid;
      S0_Ready  <= HBK_Ready;
    else
      S0_Ready  <= 'X';
      M_Valid   <= 'X';
      HBK_Valid <= 'X';
    end if; 
  end process;

end arch;
