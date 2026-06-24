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

library ieee;
use ieee.std_logic_1164.all;
entity IRC is
  generic (
    ADR_WIDTH       : integer := 13; -- Values in range 32..13
    THREAD_NO_WIDTH : integer :=  3;
    NUMBER_OF_IRS   : integer := 10; -- Values in range 32..1
    WITH_READYSYNC  : boolean := true
  );
  port (
    CLK         : in  std_logic;
    RESET       : in  std_logic;
    KillThreads : in  std_logic;
    -- Interrupt inputs
    Interrupt   : in  std_logic_vector(NUMBER_OF_IRS-1 downto 0);
    -- Wishbone bus
    WB_STB      : in  std_logic;
    WB_ADR      : in  std_logic_vector(3 downto 2);
    WB_SEL      : in  std_logic_vector(3 downto 0);
    WB_WE       : in  std_logic;
    WB_MOSI     : in  std_logic_vector(31 downto 0);
    WB_MISO     : out std_logic_vector(31 downto 0);
    WB_ACK      : out std_logic;
    -- Thread input
    S_Valid     : in  std_logic;
    S_Ready     : out std_logic;
    S_PC        : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    S_ThNo      : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Thread output
    M_Valid     : out std_logic;
    M_Ready     : in  std_logic;
    M_PC        : out std_logic_vector(ADR_WIDTH-1 downto 0);
    M_ThNo      : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end IRC;

library ieee;
use ieee.numeric_std.all;
architecture arch of IRC is
  signal Int_Enable  : std_logic_vector(NUMBER_OF_IRS-1 downto 0);
  signal Int_Active  : std_logic_vector(NUMBER_OF_IRS-1 downto 0);
  signal BufferdIRs  : std_logic_vector(NUMBER_OF_IRS-1 downto 0);
  signal Valid       : std_logic;
  signal IntDetected : std_logic;
  signal Launch      : std_logic;
  -- Thread input
  signal Wfi_Valid   : std_logic;
  signal Wfi_Ready   : std_logic;
  signal Wfi_PC      : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal Wfi_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  --
  constant Zeros     : std_logic_vector(31 downto 0) := (others => '0');
  constant DCs       : std_logic_vector(31 downto 0) := (others => '-');
begin

  -- ReadySync from S_ to Wfi_
  ReadySync_WBB: if WITH_READYSYNC generate
    signal tmp_Valid : std_logic;
    signal tmp_Ready : std_logic;
    signal tmp_PC   : std_logic_vector(ADR_WIDTH-1 downto 0);
    signal tmp_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal S_iReady  : std_logic;
  begin
    process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          tmp_Valid <= '0';
          tmp_PC    <= (tmp_PC'range  => '-');
          tmp_ThNo  <= (tmp_ThNo'range => '-');
          S_iReady  <= '0';
        else
          S_iReady <= (not Wfi_Valid) or Wfi_Ready;
          if S_iReady='1' then
            tmp_Valid <= S_Valid;
            tmp_PC    <= S_PC;
            tmp_ThNo  <= S_ThNo;
          end if;
        end if;
      end if;
    end process;
    Wfi_Valid <= S_Valid when S_iReady='1' else tmp_Valid when S_iReady='0' else 'X';
    Wfi_PC    <= S_PC    when S_iReady='1' else tmp_PC    when S_iReady='0' else (S_PC'range  => 'X');
    Wfi_ThNo  <= S_ThNo  when S_iReady='1' else tmp_ThNo  when S_iReady='0' else (S_ThNo'range => 'X');
    S_Ready   <= S_iReady;
  end generate;

  noReadySync_WBB: if not WITH_READYSYNC generate
  begin
    Wfi_Valid <= S_Valid;
    S_Ready   <= Wfi_Ready;
    Wfi_PC    <= S_PC;
    Wfi_ThNo  <= S_ThNo;
  end generate;

  process (CLK)
  begin
    if rising_edge(CLK) then
      if RESET='1' or KillThreads='1' then
        Int_Enable <= Zeros(Int_Enable'range);
        M_PC       <= DCs(M_PC'range);
        M_ThNo     <= DCs(M_ThNo'range);
        Valid      <= '0';
      elsif RESET='0' and KillThreads='0' then
        if Wfi_Ready='1' then
          Valid  <= Wfi_Valid;
          M_PC   <= Wfi_PC;
          M_ThNo <= Wfi_ThNo;
        end if;
        if (WB_STB='1') and (WB_WE='1') and WB_SEL=("1111") then
          Int_Enable <= WB_MOSI(Int_Enable'range);
        end if;
      else
        Int_Enable <= (Int_Enable'range => 'X');
        M_PC       <= (M_PC'range => 'X');
        M_ThNo     <= (M_ThNo'range => 'X');
        Valid      <= 'X';
      end if;
      BufferdIRs <= Interrupt;
    end if;
  end Process;
  
  Wfi_Ready <= (not Valid) or Launch;
  M_Valid   <= IntDetected and Valid;
  Launch    <= IntDetected and M_Ready;
  
  Int_Active <= BufferdIRs and Int_Enable;
  
  DetectInts: process(Int_Active)
  begin
    IntDetected <= '0';
    for i in Int_Active'range loop
      if    Int_Active(i) ='1' then IntDetected <= '1';
      elsif Int_Active(i)/='0' then IntDetected <= 'X'; exit;
      end if;
    end loop;
  end process;
  
  WB_MISO <= Zeros(31 downto NUMBER_OF_IRS) & Int_Enable when WB_ADR="11" else
             Zeros(31 downto NUMBER_OF_IRS) & BufferdIRs when WB_ADR="10" else
             Zeros(31 downto NUMBER_OF_IRS) & Int_Active when WB_ADR="01" else
             Zeros(31 downto 2) & IntDetected & Valid    when WB_ADR="00" else
             (WB_MISO'range => 'X');
  
  WB_ACK <= WB_STB;
  
end arch;
