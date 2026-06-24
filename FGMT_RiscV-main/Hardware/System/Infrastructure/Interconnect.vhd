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
-- Interconnect
-- Accesses to the memory map inside an address address window from ADR0_BASE to
-- (ADR0_BASE+ADR0_SIZE-1) are routed to the MR0/MW0 output.
-- All other accesses are routed to the MR1/MW1 output.
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity Interconnect is
  generic (
    ADDR_WIDTH      : integer               :=              14; -- Number of Adressbits (including Bits 1 and 0)
    ADR0_BASE       : unsigned(31 downto 0) := (others => '0'); -- Base Address in Bytes
    ADR0_SIZE       : integer               :=            1024; -- Size of Address Window (in Bytes)
    THREAD_NO_WIDTH : integer               :=               5  -- Number of ThNo-Bits
  );
  port (
    CLK       : in  std_logic;
    RESET     : in  std_logic;
    -- Read Request Input
    SR_Valid  : in  std_logic;
    SR_Ready  : out std_logic;
    SR_ADR    : in  std_logic_vector(ADDR_WIDTH-1 downto 2);      -- 32 Bit Word address
    SR_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Read Response Output
    MR_Valid  : out std_logic;
    MR_Ready  : in  std_logic;
    MR_DAT   : out std_logic_vector(31 downto 0);
    -- Read Request Output, Channel 0
    MR0_Valid : out std_logic;
    MR0_Ready : in  std_logic;
    MR0_ADR   : out std_logic_vector(ADDR_WIDTH-1 downto 2);      -- 32 Bit Word address
    MR0_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Read Response Input, Channel 0
    SR0_Valid : in  std_logic;
    SR0_Ready : out std_logic;
    SR0_DAT  : in  std_logic_vector(31 downto 0);
    -- Read Request Output, Channel 1
    MR1_Valid : out std_logic;
    MR1_Ready : in  std_logic;
    MR1_ADR   : out std_logic_vector(ADDR_WIDTH-1 downto 2);      -- 32 Bit Word address
    MR1_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Read Response Input, Channel 1
    SR1_Valid : in  std_logic;
    SR1_Ready : out std_logic;
    SR1_DAT  : in  std_logic_vector(31 downto 0);
    -- Write Request Input
    SW_Valid  : in  std_logic;
    SW_Ready  : out std_logic;
    SW_DAT    : in  std_logic_vector(31 downto 0);
    SW_SEL    : in  std_logic_vector( 3 downto 0);
    SW_ADR    : in  std_logic_vector(ADDR_WIDTH-1 downto 2);      -- 32 Bit Word address
    SW_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Write Request Output, Channel 0
    MW0_Valid : out std_logic;
    MW0_Ready : in  std_logic;
    MW0_DAT   : out std_logic_vector(31 downto 0);
    MW0_SEL   : out std_logic_vector( 3 downto 0);
    MW0_ADR   : out std_logic_vector(ADDR_WIDTH-1 downto 2);      -- 32 Bit Word address
    MW0_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- Write Request Output, Channel 1
    MW1_Valid : out std_logic;
    MW1_Ready : in  std_logic;
    MW1_DAT   : out std_logic_vector(31 downto 0);
    MW1_SEL   : out std_logic_vector( 3 downto 0);
    MW1_ADR   : out std_logic_vector(ADDR_WIDTH-1 downto 2);      -- 32 Bit Word address
    MW1_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end Interconnect;

architecture arch of Interconnect is
  constant ADR0_LOW  : unsigned(31 downto 0) := ADR0_BASE;
  constant ADR0_HIGH : unsigned(31 downto 0) := ADR0_BASE+ADR0_SIZE-1;
  signal   Channel   : std_logic;
begin

  Read_Channels: block
    signal SR_Ready_i : std_logic;
    signal MR_Valid_i : std_logic;
    signal Inc        : std_logic;
    signal Dec        : std_logic;
    signal Zero       : std_logic;
    signal Max        : std_logic;
    signal Error      : std_logic := '0';
    signal AdrDec     : std_logic;
    type States is (CH0, CH1, X);
    signal State      : States;
    signal NextState  : States;
  begin
    
    Inc <= SR_Ready_i and SR_Valid;
    Dec <= MR_Valid_i and MR_Ready;
    
    -- counter for outstanding read responses
    Counter: process(CLK)
      variable Q    : unsigned(3 downto 0):= "0000"; -- up to 15 outstanding read responses possible, that's a lot.
      variable Err: std_logic := '0';
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          Q := (Q'range => '0');
          Err := '0';
        elsif Error='0' then
          if    Inc='1' and Dec='0' and Max='0'  then Q := Q+1;
          elsif Inc='0' and Dec='1' and Zero='0' then Q := Q-1;
          elsif Inc='0' and Dec='1' and Zero='1' then Err := '1';
          end if;
        end if;
        if Q=0 then Zero <= '1';
        else        Zero <= '0';
        end if;
        if Q=2**Q'length-1 then Max <= '1';
        else                    Max <= '0';
        end if;
        Error <= Err;
      end if;
    end process;

    AdrDec <= '0' when     (unsigned(SR_ADR&"00")>=ADR0_LOW(ADDR_WIDTH-1 downto 0))
                       and (unsigned(SR_ADR&"00")<=ADR0_HIGH(ADDR_WIDTH-1 downto 0)) else '1';

    ResponseMUX: process(Channel, MR_Ready, SR0_Valid, SR0_DAT, SR1_Valid, SR1_DAT)
    begin
      MR_DAT     <= (MR_DAT'range => 'X');
      MR_Valid_i <= 'X';
      SR0_Ready  <= 'X';
      SR1_Ready  <= 'X';
      if    Channel='0' then
        MR_DAT     <= SR0_DAT;
        MR_Valid_i <= SR0_Valid;
        SR0_Ready  <= MR_Ready;
        SR1_Ready  <= '0';
      elsif Channel='1' then
        MR_DAT     <= SR1_DAT;
        MR_Valid_i <= SR1_Valid;
        SR0_Ready  <= '0';
        SR1_Ready  <= MR_Ready;
      end if;
    end process;
    
    MR_Valid <= MR_Valid_i;
    SR_Ready <= SR_Ready_i;
    MR0_ADR  <= SR_ADR;
    MR1_ADR  <= SR_ADR;
    MR0_ThNo <= SR_ThNo;
    MR1_ThNo <= SR_ThNo;

    FSM_Next_Mealy: process(State, RESET, SR_Valid, AdrDec, Zero, Max, MR0_Ready, MR1_Ready)
    begin
      NextState  <= X;
      SR_Ready_i <= '0';
      MR0_Valid  <= '0';
      MR1_Valid  <= '0';
      if RESET='1' then
        NextState <= CH0;
      elsif RESET='0' then
        case State is
          when CH0 =>
            if (SR_Valid='0') then
              NextState <= CH0;
            elsif (SR_Valid='1') and (AdrDec='0') and (Max='0') then
              NextState  <= CH0;
              MR0_Valid  <= '1';
              SR_Ready_i <= MR0_Ready;
            elsif (SR_Valid='1') and (AdrDec='1') and (Zero='0') then
              NextState  <= CH0;
            elsif (SR_Valid='1') and (AdrDec='1') and (Zero='1') then
              NextState  <= CH1;
              MR1_Valid  <= '1';
              SR_Ready_i <= MR1_Ready;
            end if;
          when CH1   =>
            if (SR_Valid='0') then
              NextState <= CH1;
            elsif (SR_Valid='1') and (AdrDec='1') and (Max='0') then
              NextState  <= CH1;
              MR1_Valid  <= '1';
              SR_Ready_i <= MR1_Ready;
            elsif (SR_Valid='1') and (AdrDec='0') and (Zero='0') then
              NextState  <= CH1;
            elsif (SR_Valid='1') and (AdrDec='0') and (Zero='1') then
              NextState  <= CH0;
              MR0_Valid  <= '1';
              SR_Ready_i <= MR0_Ready;
            end if;
          when X =>
            SR_Ready_i <= 'X';
            MR0_Valid  <= 'X';
            MR1_Valid  <= 'X';
        end case;
      end if;
    end process;
    
    FSM_Trans_Moore: process(CLK)
    begin
      if rising_edge(CLK) then
        State <= NextState;
        case NextState is
          when CH0 => Channel <= '0';
          when CH1 => Channel <= '1';
          when X   => Channel <= 'X';
        end case;
      end if;
    end process;

  end block;

  WriteChannels: process(SW_Valid, SW_DAT, SW_SEL, SW_ADR, SW_ThNo, MW0_Ready, MW1_Ready)
  begin
    SW_Ready  <= '0';
    MW0_Valid <= '0';
    MW0_DAT   <= SW_DAT;
    MW0_SEL   <= SW_SEL;
    MW0_ADR   <= SW_ADR;
    MW0_ThNo  <= SW_ThNo;
    MW1_Valid <= '0';
    MW1_DAT   <= SW_DAT;
    MW1_SEL   <= SW_SEL;
    MW1_ADR   <= SW_ADR;
    MW1_ThNo  <= SW_ThNo;
    if     (unsigned(SW_ADR&"00")>=ADR0_LOW(ADDR_WIDTH-1 downto 0))
       and (unsigned(SW_ADR&"00")<=ADR0_HIGH(ADDR_WIDTH-1 downto 0)) then
      MW0_Valid <= SW_Valid;
      SW_Ready  <= MW0_Ready;
    else
      MW1_Valid <= SW_Valid;
      SW_Ready  <= MW1_Ready;
    end if;
  end process;
  
end arch;
