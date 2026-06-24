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
-- WriteRegisters
-- This pipeline stage writes a result value if required to the result register
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity WriteRegister is 
  generic (
    INST_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  5
  );
  port (
    CLK       : in  std_logic;
    RESET     : in  std_logic;
    -- Input from Instruction DMUX
    S_Valid   : in  std_logic;
    S_Ready   : out std_logic;
    S_PC      : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_ThNo    : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_rdV     : in  std_logic_vector(31 downto 0);
    S_rd      : in  std_logic_vector( 4 downto 0);
    -- Stream to register write
    MW_Valid  : out std_logic;
    MW_Ready  : in  std_logic;
    MW_ADR    : out std_logic_vector((THREAD_NO_WIDTH+5)-1 downto 0);
    MW_rdV    : out std_logic_vector(31 downto 0);
    -- Injection Interface
    IJ_Active : in  std_logic;
    IJ_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    IJ_RegV   : out std_logic_vector(31 downto 0);
    -- Output to Function DMUX
    M_Valid   : out std_logic;
    M_Ready   : in  std_logic;
    M_PC      : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end WriteRegister;

library ieee;
use ieee.numeric_std.all;
architecture arch of WriteRegister is
  signal GTZ         : std_logic;
  signal S_iReady    : std_logic;
  signal IJ_eq       : std_logic;
begin

  GTZ <= '1' when unsigned(S_rd)>0 else '0';

  FSM: block
    type States is (WrDestReg, MW_Wait, M_Wait, error);
    signal State      : States;
    signal NextState  : States;
  begin
    process (State, RESET, S_Valid, GTZ, MW_Ready, M_Ready)
    begin
      NextState  <= error;
      S_iReady   <= '0';
      MW_Valid   <= '0';
      M_Valid    <= '0';
      if RESET='1' then
        NextState  <= WrDestReg;
      elsif RESET='0' then
        case State is
          when WrDestReg => -- Write destination register
            if (S_Valid='0') then
              NextState <= WrDestReg;
              
            elsif (S_Valid='1') and (GTZ='0') then
              NextState <= WrDestReg;
              M_Valid <='1';
              if (M_Ready='1') then
                S_iReady <='1';
              end if;
              
            elsif (S_Valid='1') and (GTZ='1') then
              MW_Valid <='1';
              M_Valid  <='1';
              if    (MW_Ready='0') and (M_Ready='0') then
                NextState <= WrDestReg;
              elsif (MW_Ready='0') and (M_Ready='1') then
                NextState <= MW_Wait;
              elsif (MW_Ready='1') and (M_Ready='0') then
                NextState <= M_Wait;
              elsif (MW_Ready='1') and (M_Ready='1') then
                NextState <= WrDestReg;
                S_iReady  <='1';
              end if;
            end if;
          when M_Wait =>
            M_Valid <= '1';
            if (M_Ready='0') then
              NextState <= M_Wait;
            elsif (M_Ready='1') then
              NextState <= WrDestReg;
              S_iReady  <='1';
            end if;
          when MW_Wait =>
            MW_Valid  <= '1';
            if (MW_Ready='0') then
              NextState <= MW_Wait;
            elsif (MW_Ready='1') then
              NextState <= WrDestReg;
              S_iReady  <='1';
            end if;
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

  MW_ADR <= S_ThNo & S_rd;
  MW_rdV <= S_rdV;

  M_PC    <= S_PC;
  M_ThNo  <= S_ThNo;
  S_Ready <= S_iReady;

  IJ_eq <= '1' when S_ThNo=IJ_ThNo else '0';
  
  IJ_reg: process (CLK)
  begin
    if rising_edge(CLK) then
      if RESET='1' then
        IJ_RegV <= (IJ_RegV'range => '-');
      elsif (IJ_Active='1') and (S_iReady='1') and (IJ_eq='1') then
        IJ_RegV <= S_rdV;
      end if;
    end if;
  end process;

end arch;