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

entity ClockManager is
    generic (
        CLKIN_PERIOD : real;
        CLKMUL       : real;
        CLKDIV       : integer
    );
    port (
        clkin  : in  std_logic;
        clkout : out std_logic;
        locked : out std_logic
    );
end entity;

library unisim;
use unisim.vcomponents.all;

architecture synth of ClockManager is 
    signal clkfb : std_logic;
begin
   -- MMCME2_BASE: Base Mixed Mode Clock Manager
   --              Artix-7
   -- Xilinx HDL Language Template, version 2017.4
    MMCME2_BASE_inst : MMCME2_BASE
     generic map (
        BANDWIDTH => "OPTIMIZED",        -- Jitter programming (OPTIMIZED, HIGH, LOW)
        CLKFBOUT_MULT_F => CLKMUL,       -- Multiply value for all CLKOUT (2.000-64.000).
        CLKFBOUT_PHASE  => 0.0,          -- Phase offset in degrees of CLKFB (-360.000-360.000).
        CLKIN1_PERIOD   => CLKIN_PERIOD, -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
        -- CLKOUT0_DIVIDE - CLKOUT6_DIVIDE: Divide amount for each CLKOUT (1-128)
        CLKOUT1_DIVIDE   => CLKDIV,
        CLKOUT2_DIVIDE   => 1,
        CLKOUT3_DIVIDE   => 1,
        CLKOUT4_DIVIDE   => 1,
        CLKOUT5_DIVIDE   => 1,
        CLKOUT6_DIVIDE   => 1,
        CLKOUT0_DIVIDE_F => 1.0,   -- Divide amount for CLKOUT0 (1.000-128.000).
        -- CLKOUT0_DUTY_CYCLE - CLKOUT6_DUTY_CYCLE: Duty cycle for each CLKOUT (0.01-0.99).
        CLKOUT0_DUTY_CYCLE => 0.5,
        CLKOUT1_DUTY_CYCLE => 0.5,
        CLKOUT2_DUTY_CYCLE => 0.5,
        CLKOUT3_DUTY_CYCLE => 0.5,
        CLKOUT4_DUTY_CYCLE => 0.5,
        CLKOUT5_DUTY_CYCLE => 0.5,
        CLKOUT6_DUTY_CYCLE => 0.5,
        -- CLKOUT0_PHASE - CLKOUT6_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
        CLKOUT0_PHASE   => 0.0,
        CLKOUT1_PHASE   => 0.0,
        CLKOUT2_PHASE   => 0.0,
        CLKOUT3_PHASE   => 0.0,
        CLKOUT4_PHASE   => 0.0,
        CLKOUT5_PHASE   => 0.0,
        CLKOUT6_PHASE   => 0.0,
        CLKOUT4_CASCADE => FALSE,  -- Cascade CLKOUT4 counter with CLKOUT6 (FALSE, TRUE)
        DIVCLK_DIVIDE   => 1,      -- Master division value (1-106)
        REF_JITTER1     => 0.0,    -- Reference input jitter in UI (0.000-0.999).
        STARTUP_WAIT    => FALSE   -- Delays DONE until MMCM is locked (FALSE, TRUE)
      )
      port map (
        -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
        CLKOUT0   => open,   -- 1-bit output: CLKOUT0
        CLKOUT0B  => open,   -- 1-bit output: Inverted CLKOUT0
        CLKOUT1   => CLKOUT, -- 1-bit output: CLKOUT1
        CLKOUT1B  => open,   -- 1-bit output: Inverted CLKOUT1
        CLKOUT2   => open,   -- 1-bit output: CLKOUT2
        CLKOUT2B  => open,   -- 1-bit output: Inverted CLKOUT2
        CLKOUT3   => open,   -- 1-bit output: CLKOUT3
        CLKOUT3B  => open,   -- 1-bit output: Inverted CLKOUT3
        CLKOUT4   => open,   -- 1-bit output: CLKOUT4
        CLKOUT5   => open,   -- 1-bit output: CLKOUT5
        CLKOUT6   => open,   -- 1-bit output: CLKOUT6
        -- Feedback Clocks: 1-bit (each) output: Clock feedback ports
        CLKFBOUT  => clkfb,  -- 1-bit output: Feedback clock
        CLKFBOUTB => open,   -- 1-bit output: Inverted CLKFBOUT
        -- Status Ports: 1-bit (each) output: MMCM status ports
        LOCKED    => locked, -- 1-bit output: LOCK
        -- Clock Inputs: 1-bit (each) input: Clock input
        CLKIN1    => clkin,  -- 1-bit input: Clock
        -- Control Ports: 1-bit (each) input: MMCM control ports
        PWRDWN    => '0',    -- 1-bit input: Power-down
        RST       => '0',    -- 1-bit input: Reset
        -- Feedback Clocks: 1-bit (each) input: Clock feedback ports
        CLKFBIN   => clkfb   -- 1-bit input: Feedback clock
      );

   -- End of PLLE2_BASE_inst instantiation
end architecture;
