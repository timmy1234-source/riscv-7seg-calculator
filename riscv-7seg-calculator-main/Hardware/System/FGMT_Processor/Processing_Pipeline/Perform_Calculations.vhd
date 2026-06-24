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
-- Perform_Calculations
-- This pipeline stage performs the calculations on the source operands 
-- (c) Bernhard Lang
---------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
entity Perform_Calculations is
  generic (
    INST_ADDR_WIDTH : integer := 32;
    DATA_ADDR_WIDTH : integer := 32;
    THREAD_NO_WIDTH : integer :=  5
  );
  port (
    -- Input
    S_Valid  : in  std_logic;
    S_Ready  : out std_logic;
    S_PC     : in  std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    S_ThNo   : in  std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    S_Imm12  : in  std_logic_vector(11 downto 0);
    S_rs1V   : in  std_logic_vector(31 downto 0);
    S_rs2V   : in  std_logic_vector(31 downto 0);
    S_rd     : in  std_logic_vector( 4 downto 0);
    S_cmd    : in  std_logic_vector(10 downto 0);
    -- Output
    M_Valid  : out std_logic;
    M_Ready  : in  std_logic;
    M_PC     : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    M_ThNo   : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    M_rdV    : out std_logic_vector(31 downto 0);
    M_rd     : out std_logic_vector( 4 downto 0);
    -- Error Output
    Mx_Valid : out std_logic;
    Mx_Ready : in  std_logic;
    Mx_PC    : out std_logic_vector(INST_ADDR_WIDTH-1 downto 0);
    Mx_ThNo  : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0)
  );
end Perform_Calculations;

library ieee;
use ieee.numeric_std.all;
architecture arch of Perform_Calculations is
begin


  process (S_Valid, M_Ready, Mx_Ready, S_PC, S_ThNo, S_Imm12, S_rs1V, S_rs2V, S_rd, S_cmd)
    constant Zeros : std_logic_vector(31 downto INST_ADDR_WIDTH) := (others => '0');
    --                                             Bits       |14..12 |  6..0   |
    constant cmd_JALR  : std_logic_vector(10 downto 0) := "0" & "000" & "1100111";
    constant cmd_BEQ   : std_logic_vector(10 downto 0) := "0" & "000" & "1100011";
    constant cmd_BNE   : std_logic_vector(10 downto 0) := "0" & "001" & "1100011";
    constant cmd_BLT   : std_logic_vector(10 downto 0) := "0" & "100" & "1100011";
    constant cmd_BGE   : std_logic_vector(10 downto 0) := "0" & "101" & "1100011";
    constant cmd_BLTU  : std_logic_vector(10 downto 0) := "0" & "110" & "1100011";
    constant cmd_BGEU  : std_logic_vector(10 downto 0) := "0" & "111" & "1100011";
    constant cmd_ADDI  : std_logic_vector(10 downto 0) := "0" & "000" & "0010011";
    constant cmd_SLTI  : std_logic_vector(10 downto 0) := "0" & "010" & "0010011";
    constant cmd_SLTIU : std_logic_vector(10 downto 0) := "0" & "011" & "0010011";
    constant cmd_XORI  : std_logic_vector(10 downto 0) := "0" & "100" & "0010011";
    constant cmd_ORI   : std_logic_vector(10 downto 0) := "0" & "110" & "0010011";
    constant cmd_ANDI  : std_logic_vector(10 downto 0) := "0" & "111" & "0010011";
    constant cmd_SLLI  : std_logic_vector(10 downto 0) := "0" & "001" & "0010011";
    constant cmd_SRLI  : std_logic_vector(10 downto 0) := "0" & "101" & "0010011";
    constant cmd_SRAI  : std_logic_vector(10 downto 0) := "1" & "101" & "0010011";
    constant cmd_ADD   : std_logic_vector(10 downto 0) := "0" & "000" & "0110011";
    constant cmd_SUB   : std_logic_vector(10 downto 0) := "1" & "000" & "0110011";
    constant cmd_SLL   : std_logic_vector(10 downto 0) := "0" & "001" & "0110011";
    constant cmd_SLT   : std_logic_vector(10 downto 0) := "0" & "010" & "0110011";
    constant cmd_SLTU  : std_logic_vector(10 downto 0) := "0" & "011" & "0110011";
    constant cmd_XOR   : std_logic_vector(10 downto 0) := "0" & "100" & "0110011";
    constant cmd_SRL   : std_logic_vector(10 downto 0) := "0" & "101" & "0110011";
    constant cmd_SRA   : std_logic_vector(10 downto 0) := "1" & "101" & "0110011";
    constant cmd_OR    : std_logic_vector(10 downto 0) := "0" & "110" & "0110011";
    constant cmd_AND   : std_logic_vector(10 downto 0) := "0" & "111" & "0110011";
    variable tmp       : std_logic_vector(31 downto 0);
    variable SignExt   : std_logic_vector(31 downto 0);
  begin
    Mx_Valid <= '0';
    Mx_PC    <= (M_PC'range => '-');
    Mx_ThNo  <= (M_ThNo'range => '-');
    if S_Valid='0' then
      M_Valid <= '0';
      M_PC    <= (M_PC'range => '-');
      M_ThNo  <= (M_ThNo'range => '-');
      M_rdV   <= (M_rdV'range =>'-');
      M_rd    <= (M_rd'range =>'-');
      S_Ready <= '-';
    elsif S_Valid='1' then
      M_Valid <= '1';
      S_Ready <= M_Ready;
      M_PC    <= S_PC;
      M_ThNo  <= S_ThNo;
      M_rdV   <= (M_rdV'range =>'-');
      M_rd    <= S_rd;
    else
      M_Valid <= 'X';
      S_Ready <= 'X';
      M_PC    <= (M_PC'range => 'X');
      M_ThNo  <= (M_ThNo'range => 'X');
      M_rdV   <= (M_rdV'range =>'X');
      M_rd    <= (M_rd'range =>'X');
    end if;
    if S_cmd=cmd_JALR then
      M_rdV <= Zeros & S_PC;
      tmp   := std_logic_vector(signed(S_rs1V) + signed(S_Imm12));
      M_PC  <= tmp(INST_ADDR_WIDTH-1 downto 0);
    elsif S_cmd=cmd_BEQ then
      if S_rs1V=S_rs2V then
        M_PC <= std_logic_vector(signed(S_PC)-4 + signed(S_Imm12&'0'));
      end if;
    elsif S_cmd=cmd_BNE then
      if S_rs1V/=S_rs2V then
        M_PC <= std_logic_vector(signed(S_PC)-4 + signed(S_Imm12&'0'));
      end if;
    elsif S_cmd=cmd_BLT then
      if signed(S_rs1V)<signed(S_rs2V) then
        M_PC <= std_logic_vector(signed(S_PC)-4 + signed(S_Imm12&'0'));
      end if;
    elsif S_cmd=cmd_BGE then
      if signed(S_rs1V)>=signed(S_rs2V) then
        M_PC <= std_logic_vector(signed(S_PC)-4 + signed(S_Imm12&'0'));
      end if;
    elsif S_cmd=cmd_BLTU then
      if unsigned(S_rs1V)<unsigned(S_rs2V) then
        M_PC <= std_logic_vector(signed(S_PC)-4 + signed(S_Imm12&'0'));
      end if;
    elsif S_cmd=cmd_BGEU then
      if unsigned(S_rs1V)>=unsigned(S_rs2V) then
        M_PC <= std_logic_vector(signed(S_PC)-4 + signed(S_Imm12&'0'));
      end if;
    elsif S_cmd=cmd_ADDI then
      M_rdV <= std_logic_vector(signed(S_rs1V) + signed(S_imm12));
    elsif S_cmd=cmd_SLTI then
      if signed(S_rs1V)<signed(S_imm12) then M_rdV <= x"00000001";
      else                                   M_rdV <= x"00000000";
      end if;
    elsif S_cmd=cmd_SLTIU then
      if unsigned(S_rs1V)<unsigned(S_imm12) then M_rdV <= x"00000001";
      else                                       M_rdV <= x"00000000";
      end if;
    elsif S_cmd=cmd_XORI then
      SignExt := (SignExt'range => S_imm12(11));
      M_rdV <= S_rs1V xor (SignExt(31 downto 12) & S_imm12);
    elsif S_cmd=cmd_ORI then 
      SignExt := (SignExt'range => S_imm12(11));
      M_rdV <= S_rs1V  or (SignExt(31 downto 12) & S_imm12);
    elsif S_cmd=cmd_ANDI then
      SignExt := (SignExt'range => S_imm12(11));
      M_rdV <= S_rs1V and (SignExt(31 downto 12) & S_imm12);
    elsif S_cmd=cmd_SLLI then
      tmp := S_rs1V;
      if S_imm12(4)='1' then tmp := tmp(15 downto 0)&"0000000000000000"; end if;
      if S_imm12(3)='1' then tmp := tmp(23 downto 0)&"00000000";         end if;
      if S_imm12(2)='1' then tmp := tmp(27 downto 0)&"0000";             end if;
      if S_imm12(1)='1' then tmp := tmp(29 downto 0)&"00";               end if;
      if S_imm12(0)='1' then tmp := tmp(30 downto 0)&"0";                end if;
      M_rdV <= tmp;
    elsif S_cmd=cmd_SRLI then
      tmp := S_rs1V;
      if S_imm12(4)='1' then tmp := "0000000000000000"&tmp(31 downto 16); end if;
      if S_imm12(3)='1' then tmp := "00000000"&tmp(31 downto 8);          end if;
      if S_imm12(2)='1' then tmp := "0000"&tmp(31 downto 4);              end if;
      if S_imm12(1)='1' then tmp := "00"&tmp(31 downto 2);                end if;
      if S_imm12(0)='1' then tmp := "0"&tmp(31 downto 1);                 end if;
      M_rdV <= tmp;
    elsif S_cmd=cmd_SRAI then
      tmp := S_rs1V;
      SignExt := (SignExt'range => tmp(31));
      if S_imm12(4)='1' then tmp := SignExt(15 downto 0)&tmp(31 downto 16); end if;
      if S_imm12(3)='1' then tmp := SignExt( 7 downto 0)&tmp(31 downto  8); end if;
      if S_imm12(2)='1' then tmp := SignExt( 3 downto 0)&tmp(31 downto  4); end if;
      if S_imm12(1)='1' then tmp := SignExt( 1 downto 0)&tmp(31 downto  2); end if;
      if S_imm12(0)='1' then tmp := SignExt( 0 downto 0)&tmp(31 downto  1); end if;
      M_rdV <= tmp;
    elsif S_cmd=cmd_ADD then
      M_rdV <= std_logic_vector(signed(S_rs1V) + signed(S_rs2V));
    elsif S_cmd=cmd_SUB then
      M_rdV <= std_logic_vector(signed(S_rs1V) - signed(S_rs2V));
    elsif S_cmd=cmd_SLT then
      if signed(S_rs1V)<signed(S_rs2V) then M_rdV <= x"00000001";
      else                                  M_rdV <= x"00000000";
      end if;
    elsif S_cmd=cmd_SLTU then
      if unsigned(S_rs1V)<unsigned(S_rs2V) then M_rdV <= x"00000001";
      else                                      M_rdV <= x"00000000";
      end if;
    elsif S_cmd=cmd_SLL then
      tmp := S_rs1V;
      if S_rs2V(4)='1' then tmp := tmp(15 downto 0)&"0000000000000000"; end if;
      if S_rs2V(3)='1' then tmp := tmp(23 downto 0)&"00000000";         end if;
      if S_rs2V(2)='1' then tmp := tmp(27 downto 0)&"0000";             end if;
      if S_rs2V(1)='1' then tmp := tmp(29 downto 0)&"00";               end if;
      if S_rs2V(0)='1' then tmp := tmp(30 downto 0)&"0";                end if;
      M_rdV <= tmp;
    elsif S_cmd=cmd_SRL then
      tmp := S_rs1V;
      if S_rs2V(4)='1' then tmp := "0000000000000000"&tmp(31 downto 16); end if;
      if S_rs2V(3)='1' then tmp := "00000000"&tmp(31 downto 8);          end if;
      if S_rs2V(2)='1' then tmp := "0000"&tmp(31 downto 4);              end if;
      if S_rs2V(1)='1' then tmp := "00"&tmp(31 downto 2);                end if;
      if S_rs2V(0)='1' then tmp := "0"&tmp(31 downto 1);                 end if;
      M_rdV <= tmp;
    elsif S_cmd=cmd_SRA then
      tmp := S_rs1V;
      SignExt := (SignExt'range => tmp(31));
      if S_rs2V(4)='1' then tmp := SignExt(15 downto 0)&tmp(31 downto 16); end if;
      if S_rs2V(3)='1' then tmp := SignExt( 7 downto 0)&tmp(31 downto  8); end if;
      if S_rs2V(2)='1' then tmp := SignExt( 3 downto 0)&tmp(31 downto  4); end if;
      if S_rs2V(1)='1' then tmp := SignExt( 1 downto 0)&tmp(31 downto  2); end if;
      if S_rs2V(0)='1' then tmp := SignExt( 0 downto 0)&tmp(31 downto  1); end if;
      M_rdV <= tmp;
    elsif S_cmd=cmd_XOR then
      M_rdV <= S_rs1V xor S_rs2V;
    elsif S_cmd=cmd_OR then --   
      M_rdV <= S_rs1V or S_rs2V;
    elsif S_cmd=cmd_AND then
      M_rdV <= S_rs1V and S_rs2V;
    else 
      Mx_Valid    <= '1';
      S_Ready     <= Mx_Ready;
      Mx_PC       <= S_PC;
      Mx_ThNo     <= S_ThNo;
    end if;
  end process;

end arch;