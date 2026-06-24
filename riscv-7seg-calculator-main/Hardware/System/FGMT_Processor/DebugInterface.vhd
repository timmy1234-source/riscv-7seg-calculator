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
-- DebugInterface
-- Used to debug FGMT-RiscV threads
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
entity DebugInterface is
  generic (
    ADR_WIDTH       : integer := 13; -- Values in range 32..13
    THREAD_NO_WIDTH : integer :=  3
  );
  port(
    CLK           : in  std_logic;
    RESET         : in  std_logic;
    -- Wishbone bus
    WB_STB        : in  std_logic;
    WB_ADR        : in  std_logic_vector(5 downto 2);
    WB_SEL        : in  std_logic_vector(3 downto 0);
    WB_WE         : in  std_logic;
    WB_MOSI       : in  std_logic_vector(31 downto 0);
    WB_MISO       : out std_logic_vector(31 downto 0);
    WB_ACK        : out std_logic;
    -- Debug Streaming Input
    DBG_Valid     : in  std_logic;
    DBG_Ready     : out std_logic;
    DBG_PC        : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    DBG_ThNo      : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Ebreak Streaming Input
    EBK_Valid     : in  std_logic;
    EBK_Ready     : out std_logic;
    EBK_PC        : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    EBK_ThNo      : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Hardware Breakpoint Streaming Input
    HBK_Valid     : in  std_logic;
    HBK_Ready     : out std_logic;
    HBK_PC        : in  std_logic_vector(ADR_WIDTH-1 downto 0);
    HBK_ThNo      : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Inputs and Outputs
    TF_ThBits     : out std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    IJ_Inst       : out std_logic_vector(31 downto 0);
    IJ_Active     : out std_logic;
    IJ_ThNo       : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    IJ_RegV       : in  std_logic_vector(31 downto 0);
    KillThreads   : out std_logic;
    DBI_Interrupt : out std_logic
  );
end DebugInterface;

library IEEE;
use IEEE.numeric_std.all;
architecture arch of DebugInterface is
  signal Sel_ThBits   : std_logic;
  signal Sel_Inst     : std_logic;
  signal Sel_Active   : std_logic;
  signal Sel_KillThs  : std_logic;
  signal iKillThreads : std_logic;
  signal ConsumeDTh   : std_logic;
  signal DTh_Valid    : std_logic;
  signal DTh_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal DTh_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal ConsumeETh   : std_logic;
  signal ETh_Valid    : std_logic;
  signal ETh_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal ETh_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal ConsumeHTh   : std_logic;
  signal HTh_Valid    : std_logic;
  signal HTh_PC       : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal HTh_ThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal TF_iThBits   : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
  signal DBG_iReady   : std_logic;
  signal EBK_iReady   : std_logic;
  signal HBK_iReady   : std_logic;
  signal IJ_iInst     : std_logic_vector(31 downto 0);
  signal IJ_iActive   : std_logic;
  signal IJ_iThNo     : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  constant Zeros           : std_logic_vector(31 downto 0) := (others => '0');
  constant ADR_ID          : std_logic_vector( 5 downto 2) := "0000"; -- offset 0x00
  constant ADR_STATUS      : std_logic_vector( 5 downto 2) := "0001"; -- offset 0x04
  constant ADR_TF_THBITS   : std_logic_vector( 5 downto 2) := "0010"; -- offset 0x08
  constant ADR_KillThreads : std_logic_vector( 5 downto 2) := "0011"; -- offset 0x0C
  constant ADR_IJ_REGV     : std_logic_vector( 5 downto 2) := "0100"; -- offset 0x10
  constant ADR_IJ_ACTIVE   : std_logic_vector( 5 downto 2) := "0101"; -- offset 0x14
  constant ADR_IJ_INST     : std_logic_vector( 5 downto 2) := "0110"; -- offset 0x18
  constant ADR_DTh_PC      : std_logic_vector( 5 downto 2) := "1000"; -- offset 0x20
  constant ADR_DTh_THNO    : std_logic_vector( 5 downto 2) := "1001"; -- offset 0x24
  constant ADR_ETh_PC      : std_logic_vector( 5 downto 2) := "1010"; -- offset 0x28
  constant ADR_ETh_THNO    : std_logic_vector( 5 downto 2) := "1011"; -- offset 0x2C
  constant ADR_HTh_PC      : std_logic_vector( 5 downto 2) := "1100"; -- offset 0x30
  constant ADR_HTh_THNO    : std_logic_vector( 5 downto 2) := "1101"; -- offset 0x34
  constant ID_DBG_IF       : std_logic_vector(31 downto 0) := x"DB1F0000"; -- ID of the Debugging_Interface
begin

  Decode: process(WB_STB, WB_ADR, WB_SEL, WB_WE)
    constant ACK_OK:          std_logic := '1';
    constant ACK_no_Function: std_logic := '1'; -- WB_ACK value when accessing unused memory location
  begin
    Sel_ThBits  <= '0';
    Sel_Inst    <= '0';
    Sel_Active  <= '0';
    Sel_KillThs <= '0';
    ConsumeDTh  <= '0';
    ConsumeETh  <= '0';
    ConsumeHTh  <= '0';
    WB_ACK      <= '0';
    if (WB_STB='1') then
      if WB_WE='0' then
        case WB_ADR is -- read registers
          when ADR_ID          => WB_ACK <= ACK_OK;
          when ADR_STATUS      => WB_ACK <= ACK_OK;
          when ADR_KillThreads => WB_ACK <= ACK_OK; 
          when ADR_DTh_PC      => WB_ACK <= ACK_OK;
          when ADR_DTh_THNO    => WB_ACK <= ACK_OK;
          when ADR_ETh_PC      => WB_ACK <= ACK_OK;
          when ADR_ETh_THNO    => WB_ACK <= ACK_OK;
          when ADR_HTh_PC      => WB_ACK <= ACK_OK;
          when ADR_HTh_THNO    => WB_ACK <= ACK_OK;
          when ADR_TF_THBITS   => WB_ACK <= ACK_OK;
          when ADR_IJ_ACTIVE   => WB_ACK <= ACK_OK;
          when ADR_IJ_INST     => WB_ACK <= ACK_OK;
          when ADR_IJ_REGV     => WB_ACK <= ACK_OK;
          when others          => null;
        end case;
      elsif (WB_WE='1') and (WB_SEL="1111") then -- write registers
        case WB_ADR is
          when ADR_ID          => WB_ACK <= ACK_no_Function; 
          when ADR_STATUS      => WB_ACK <= ACK_no_Function; 
          when ADR_KillThreads => WB_ACK <= ACK_OK;          Sel_KillThs <= '1';
          when ADR_DTh_PC      => WB_ACK <= ACK_no_Function; 
          when ADR_DTh_THNO    => WB_ACK <= ACK_OK;          ConsumeDTh  <= '1'; -- Consume Thread
          when ADR_ETh_PC      => WB_ACK <= ACK_no_Function;             
          when ADR_ETh_THNO    => WB_ACK <= ACK_OK;          ConsumeETh  <= '1'; -- Consume Thread
          when ADR_HTh_PC      => WB_ACK <= ACK_no_Function;             
          when ADR_HTh_THNO    => WB_ACK <= ACK_OK;          ConsumeHTh  <= '1'; -- Consume Thread
          when ADR_TF_THBITS   => WB_ACK <= ACK_OK;          Sel_ThBits  <= '1'; -- ThBits
          when ADR_IJ_ACTIVE   => WB_ACK <= ACK_OK;          Sel_Active  <= '1'; -- IJ: Active, ThNo
          when ADR_IJ_INST     => WB_ACK <= ACK_OK;          Sel_Inst    <= '1'; -- Inst
          when ADR_IJ_REGV     => WB_ACK <= ACK_no_Function;
          when others =>
        end case;
      end if;
    end if;
  end process;  

  WB_MISO <= ID_DBG_IF                                                when WB_ADR=ADR_ID          else
             Zeros(31 downto 2)      & ETh_Valid & DTh_Valid          when WB_ADR=ADR_STATUS      else
             Zeros(31 downto ADR_WIDTH)          & DTh_PC             when WB_ADR=ADR_DTh_PC      else
             Zeros(31 downto 1)                  & iKillThreads       when WB_ADR=ADR_KillThreads else
             Zeros(31 downto THREAD_NO_WIDTH)    & DTh_ThNo           when WB_ADR=ADR_DTh_THNO    else
             Zeros(31 downto ADR_WIDTH)          & ETh_PC             when WB_ADR=ADR_ETh_PC      else
             Zeros(31 downto THREAD_NO_WIDTH)    & ETh_ThNo           when WB_ADR=ADR_ETh_THNO    else
             Zeros(31 downto ADR_WIDTH)          & HTh_PC             when WB_ADR=ADR_HTh_PC      else
             Zeros(31 downto THREAD_NO_WIDTH)    & HTh_ThNo           when WB_ADR=ADR_HTh_THNO    else
             IJ_RegV                                                  when WB_ADR=ADR_IJ_REGV     else
             IJ_iActive & Zeros(30 downto THREAD_NO_WIDTH) & IJ_iThNo when WB_ADR=ADR_IJ_ACTIVE   else
             IJ_iInst                                                 when WB_ADR=ADR_IJ_INST     else
             Zeros(31 downto 2**THREAD_NO_WIDTH) & TF_iThBits         when WB_ADR=ADR_TF_THBITS   else
             (others => '-');

  process (CLK)
  begin
    if rising_edge(CLK) then
      if    RESET='1' then
        DTh_Valid   <= '0';
        ETh_Valid   <= '0';
        DTh_PC      <= (others => '-');
        DTh_ThNo    <= (others => '-');
        ETh_PC      <= (others => '-');
        ETh_ThNo    <= (others => '-');
        HTh_PC      <= (others => '-');
        HTh_ThNo    <= (others => '-');
        TF_iThBits  <= (others => '0');
        IJ_iInst    <= (others => '-');
        IJ_iThNo    <= (others => '0');
        IJ_iActive  <= '0';
        iKillThreads <= '0';
      elsif RESET='0'        then
        -- TF_ThBits register
        if    DTh_Valid='1'  then TF_iThBits  <= (TF_ThBits'range => '0');
        elsif Sel_ThBits='1' then TF_iThBits  <= WB_MOSI(TF_ThBits'range);
        end if;
        -- IJ_Inst register
        if    Sel_Inst='1'   then IJ_iInst    <= WB_MOSI(IJ_Inst'range);
        end if;
        -- IJ_ThNo register
        if    Sel_Active='1' then IJ_iThNo    <= WB_MOSI(IJ_ThNo'range);
                                  IJ_iActive  <= WB_MOSI(31);
        end if;
        -- KillThreads register
        if Sel_KillThs='1'   then iKillThreads <= WB_MOSI(0);
        end if;
        -- DBG DataSync register 
        if DBG_iReady='1' then
          DTh_Valid <= DBG_Valid;
          DTh_PC    <= DBG_PC;
          DTh_ThNo  <= DBG_ThNo;
        end if;
        -- EBK DataSync register 
        if EBK_iReady='1' then
          ETh_Valid <= EBK_Valid;
          ETh_PC    <= EBK_PC;
          ETh_ThNo  <= EBK_ThNo;
        end if;
        -- HBK DataSync register 
        if HBK_iReady='1' then
          HTh_Valid <= HBK_Valid;
          HTh_PC    <= HBK_PC;
          HTh_ThNo  <= HBK_ThNo;
        end if;
      end if;
    end if;
  end Process;
  
  TF_ThBits   <= TF_iThBits;
  IJ_Inst     <= IJ_iInst;
  IJ_Active   <= IJ_iActive;
  IJ_ThNo     <= IJ_iThNo;
  KillThreads <= iKillThreads;

  -- DBG DataSync control 
  DBG_iReady <= (not DTh_Valid) or ConsumeDTh;
  DBG_Ready  <= DBG_iReady;

  -- EBK DataSync control 
  EBK_iReady <= (not ETh_Valid) or ConsumeETh;
  EBK_Ready  <= EBK_iReady;

  -- HBK DataSync control 
  HBK_iReady <= (not HTh_Valid) or ConsumeHTh;
  HBK_Ready  <= HBK_iReady;

  DBI_Interrupt <= ETh_Valid or HTh_Valid;

end arch;