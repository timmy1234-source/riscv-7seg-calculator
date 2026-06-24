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
use ieee.numeric_std.all;

entity FGMT_System_BASYS3 is
  port(
    -- External Clock
    ExtClk      : in    std_logic;
    -- Serial GDB Interface 
    GDB_RxD     : in    std_logic;
    GDB_TxD     : out   std_logic;
    -- Diagnostic outputs
    DigitSelect : out   std_logic_vector(3 downto 0);
    DigitBits   : out   std_logic_vector(7 downto 0);
    -- User I/O
    BUTTON      : inout std_logic_vector( 4 downto 0);
    LED         : out   std_logic_vector(15 downto 0);
    SW          : in    std_logic_vector(15 downto 0)
  );
end FGMT_System_BASYS3;

architecture arch of FGMT_System_BASYS3 is

  constant ExtClk_Frequency : integer := 100_000_000;
  constant CLKMUL           : real    := real(8);
  constant CLKDIV           : integer := 16;
  constant SYS_FREQUENCY    : integer := integer(Real(CLKMUL) * real(ExtClk_Frequency) / real(CLKDIV) + 0.5);
  constant CLKIN_PERIOD     : real    := real(1_000_000_000) / real(ExtClk_Frequency); -- ns pro ExtClk-Periode
                            
  constant HEX_FILE_FGMT    : string  := "../../../Software/FGMT_GDB_Server.hex"; -- Vivado
  constant ADR_WIDTH        : integer := 16; -- Address width of FGMT-System
  constant THREAD_NO_WIDTH  : integer :=  4;  -- Width of ThreadNo-Vector
  
  signal CLK        : std_logic;
  signal locked     : std_logic;
  signal RESET      : std_logic;
  signal ActThreads : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
  signal ThActivity : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
  signal ErrVect    : std_logic_vector(31 downto 0);
  signal AxsVect    : std_logic_vector(31 downto 0); -- AxiS status of processing pipeline
  signal PINS       : std_logic_vector(24 downto 0);
  signal PWM        : std_logic;
  signal Digit0     : std_logic_vector( 3 downto 0);
  signal Digit1     : std_logic_vector( 3 downto 0);
  signal Digit2     : std_logic_vector( 3 downto 0);
  signal Digit3     : std_logic_vector( 3 downto 0);
begin

  ResetProc: process(CLK)
    variable cnt: unsigned(1 downto 0) := (others => '1');
  begin
    if rising_edge(CLK) then
      RESET <= '0';
      if locked='0' then
        RESET <= '1';
        cnt := (others => '1');
      elsif (locked='1') and (cnt>0) then
        RESET <= '1';
        cnt := cnt-1;
      else 
      RESET <= '0';
      end if;
    end if;
  end process;

  -- Generate system clock from external clock input ExtClk
  clkgen: entity work.ClockManager
    generic map (
      CLKIN_PERIOD => CLKIN_PERIOD,
      CLKMUL       => CLKMUL,
      CLKDIV       => CLKDIV
    )
    port map (
      clkin  => ExtClk,
      locked => locked,
      clkout => CLK
    );

  -- The FGMT-RiscV
  FGMT_System_inst: entity work.FGMT_System
    generic map (
      Frequency           => SYS_FREQUENCY,
      ADR_WIDTH           => ADR_WIDTH,
      THREAD_NO_WIDTH     => THREAD_NO_WIDTH,
      ERR_ID_WIDTH        =>  2,
      TH_ACTIVITY_TIMEOUT => 15,
      HEX_FILE            => HEX_FILE_FGMT
    )
    port map (
      CLK        => CLK,
      RESET      => RESET,
      -- Diagnostic outputs
      ActThreads => ActThreads,
      ThActivity => ThActivity,
      ErrVect    => ErrVect,
      AxsVect    => AxsVect,
      -- Serial Port for GDBServer
      GDB_TxD    => GDB_TxD, -- open, -- GDB_TxD,
      GDB_RxD    => GDB_RxD,
      -- IOs from FGMT-RiscV      
      PINS       => PINS,
      PWM        => PWM,
      --
      RxD        => '1',
      TxD        => open
    );
    -- GDB_TxD <= GDB_RxD;

  SevenSeg_inst: entity work.SevenSeg
    generic map (
      Divider => 10_000
    )
    port map (
      CLK         => CLK,
      --
      EN0         => '1',
      Digit0      => Digit0,	
      DP0         => PWM,
      --
      EN1         => '1',
      Digit1      => Digit1,
      DP1         => '0',
      --
      EN2         => '1',
      Digit2      => Digit2,
      DP2         => '0',
      --
      EN3         => '1',
      Digit3      => Digit3,
      DP3         => '0',
      --
      DigitSelect => DigitSelect,
      DigitBits   => DigitBits
    );
  Digit0 <= PINS( 8 downto  5);
  Digit1 <= PINS(12 downto  9);
  Digit2 <= PINS(16 downto 13);
  Digit3 <= PINS(20 downto 17);
  PINS(4 downto 0) <= BUTTON;

  process(ActThreads, ThActivity, SW(2 downto 0))
  begin
    LED <= (others => '0');
    if THREAD_NO_WIDTH <= 4 then
        if    SW(2 downto 0)="000" then LED(ActThreads'range) <= ActThreads;
        elsif SW(2 downto 0)="001" then LED(ThActivity'range) <= ThActivity;
        elsif SW(2 downto 0)="010" then LED <= ErrVect(31 downto 16);
        elsif SW(2 downto 0)="011" then LED <= ErrVect(15 downto  0);
        elsif SW(2 downto 0)="100" then LED <= AxsVect(31 downto 16);
        elsif SW(2 downto 0)="101" then LED <= AxsVect(15 downto  0);
        end if;
    else
        if    SW(2 downto 0)="000" then LED <= ActThreads(15 downto 0);
        elsif SW(2 downto 0)="001" then LED <= ThActivity(15 downto 0);
        elsif SW(2 downto 0)="010" then LED <= ErrVect(31 downto 16);
        elsif SW(2 downto 0)="011" then LED <= ErrVect(15 downto  0);
        elsif SW(2 downto 0)="100" then LED <= AxsVect(31 downto 16);
        elsif SW(2 downto 0)="101" then LED <= AxsVect(15 downto  0);
        end if;
    end if;
  end process;

end architecture;