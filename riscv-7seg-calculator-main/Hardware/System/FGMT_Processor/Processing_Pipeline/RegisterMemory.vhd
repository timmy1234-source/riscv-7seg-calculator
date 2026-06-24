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
-- RegisterMemory
-- The register memory is described as a two port memory. One port is used to
-- read register values, the second port is used for writing. 
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity RegisterMemory is 
  generic (
    THREAD_NO_WIDTH : integer :=  5
  );
  port (
    CLK      : in  std_logic;
    RESET    : in  std_logic;
    -- Input Register read
    SR_Valid : in  std_logic;
    SR_Ready : out std_logic;
    SR_ADR1  : in  std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
    SR_ADR2  : in  std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
    SR_Sel1  : in  std_logic;
    SR_Sel2  : in  std_logic;
    -- Input Register write
    SW_Valid : in  std_logic;
    SW_Ready : out std_logic;
    SW_ADR   : in  std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
    SW_rdV   : in  std_logic_vector(31 downto 0);
    -- Output
    MR_Valid : out std_logic;
    MR_Ready : in  std_logic;
    MR_rs1V  : out std_logic_vector(31 downto 0);
    MR_rs2V  : out std_logic_vector(31 downto 0)
  );
end RegisterMemory;

library ieee;
use ieee.numeric_std.all;
architecture arch of RegisterMemory is
  signal Sel        : std_logic;
  signal RADR       : std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
  signal RDATA      : std_logic_vector(31 downto 0);
  signal rsV        : std_logic_vector(31 downto 0);
  signal equal      : std_logic := '0';
  signal EnRead     : std_logic := '0';
  signal rs2V_Valid : std_logic := '0';
  signal rs2V_Ready : std_logic := '0';
  signal Valid      : std_logic := '0';
  signal Ready      : std_logic := '0';
  signal DS_Valid   : std_logic := '0';
  signal DS_Sel     : std_logic := '0';
  type mem_array is array(0 to (2**(THREAD_NO_WIDTH+5))-1) of std_logic_vector(31 downto 0);
  signal regs : mem_array := (mem_array'range => x"00000000");
begin

  --------------------------------------------------------------------------------------------
  -- Read
  --------------------------------------------------------------------------------------------
  
  RADR <= SR_ADR1             when Sel='0' else
          SR_ADR2             when Sel='1' else
          (RADR'range => '-') when Sel='-' else
          (RADR'range => 'X');

  equal <= '1' when SR_ADR1=SR_ADR2 else '0';

  readMem: process(CLK)
  begin
    if rising_edge(CLK) then
      if EnRead='1' then
        RDATA <= regs(to_integer(unsigned(RADR)));
      end if;
    end if;
  end process;

  EnRead <= rs2V_Ready or Ready;
  
  Ready  <= (not DS_Valid) or MR_Ready;

  process (CLK)
	begin
		if rising_edge(CLK) then
      if EnRead='1' then
        DS_Sel     <= rs2V_Valid;
        rsV        <= RDATA;
        rs2V_Valid <= rs2V_Ready;
        DS_Valid   <= Valid;
      end if;
    end if;
	end process;
  
  MR_rs1V <= RDATA;
  
  MR_rs2V <= RDATA when DS_Sel='0' else
             rsV   when DS_Sel='1' else
             (MR_rs2V'range => 'X');
            
  MR_Valid <= DS_Valid and (not rs2V_Valid);
  
  FSM: block
    type States is (Run, Val2, error);
    signal State      : States;
    signal NextState  : States;
  begin
    process (State, RESET, SR_Valid, Ready, SR_Sel1, SR_Sel2, equal)
    begin
      NextState  <= error;
      Sel        <= '-';
      rs2V_Ready <= '0';
      Valid      <= '0';
      SR_Ready   <= '0';
      if RESET='1' then
        NextState  <= Run;
      elsif RESET='0' then
        case State is
          when Run =>
            if    (SR_Valid='0') or (Ready='0') then
              NextState <= Run;
            elsif (SR_Valid='1') and (Ready='1') and (SR_Sel1='0') and (SR_Sel2='1') then
              NextState <= Run;
              Sel      <='1';
              Valid    <='1';
              SR_Ready <='1';
            elsif (SR_Valid='1') and (Ready='1') and (SR_Sel1='1') and (SR_Sel2='0') then
              NextState <= Run;
              Sel      <='0';
              Valid    <='1';
              SR_Ready <='1';
            elsif (SR_Valid='1') and (Ready='1') and (SR_Sel1='1') and (SR_Sel2='1') and equal='1' then
              NextState <= Run;
              Sel      <='0';
              Valid    <='1';
              SR_Ready <='1';
            elsif (SR_Valid='1') and (Ready='1') and (SR_Sel1='1') and (SR_Sel2='1') and equal='0' then
              NextState <= Val2;
              Sel        <='1';
              rs2V_Ready <='1';
            end if;
          when Val2 =>
            NextState <= Run;
            Sel      <='0';
            Valid    <='1';
            SR_Ready <='1';
          when error => null;
        end case;
      end if;      
    end process;

    process (CLK)
    begin
      if rising_edge(CLK) then
        State <= NextState;
      end if;
    end process;

  end block;

  --------------------------------------------------------------------------------------------
  -- Write
  --------------------------------------------------------------------------------------------
  SW_Ready <= '1';
  
  writeMem: process(CLK)
  begin
    if rising_edge(CLK) then
      if SW_Valid='1' then
        regs(to_integer(unsigned(SW_ADR))) <= SW_rdV;
      end if;
    end if;
  end process;
  
end arch;