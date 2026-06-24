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

----------------------------------------------------------------------------------
-- (c) Bernhard Lang, HS Osnabrueck
-- 2024_11_16
----------------------------------------------------------------------------------

use std.textio.all; -- typen "text" und "line"
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all; -- "read"-funktion

package intel_hex_pack is

    constant NO_DEBUG_OUTPUT : boolean := true;    

    type mem_type is array (natural range<>) of std_logic_vector(31 downto 0);
    
    type half_mem_type is array (natural range<>) of std_logic_vector(15 downto 0);

    type byte_mem_type is array (natural range<>) of std_logic_vector(7 downto 0);
  
    impure function intel_hex_read(
        file_name      : in string;
        mem_base       : in natural;
        mem_size       : in natural
    ) return mem_type;
    
    impure function extract_halflane(
      halflane:    in natural;
      mem_content: in mem_type
    ) return half_mem_type;

    impure function extract_bytelane(
      bytelane:    in natural;
      mem_content: in mem_type
    ) return byte_mem_type;

end package;

package body intel_hex_pack is

    function hexchar_to_int(c : character) return integer is
        variable r : integer;
    begin
        case c is
            when '0' => r := 16#0#;
            when '1' => r := 16#1#;
            when '2' => r := 16#2#;
            when '3' => r := 16#3#;
            when '4' => r := 16#4#;
            when '5' => r := 16#5#;
            when '6' => r := 16#6#;
            when '7' => r := 16#7#;
            when '8' => r := 16#8#;
            when '9' => r := 16#9#;
            when 'a' => r := 16#a#;
            when 'b' => r := 16#b#;
            when 'c' => r := 16#c#;
            when 'd' => r := 16#d#;
            when 'e' => r := 16#e#;
            when 'f' => r := 16#f#;
            when 'A' => r := 16#A#;
            when 'B' => r := 16#B#;
            when 'C' => r := 16#C#;
            when 'D' => r := 16#D#;
            when 'E' => r := 16#E#;
            when 'F' => r := 16#F#;
            when others => 
                report "Ungueltiges Zeichen in Hex-String" severity failure;
                r := -1;
        end case;
        return r;
    end function;
    
    function hexstr_to_int(s : string(1 to 2)) return integer is
        variable r : integer := 0;
    begin
        for i in s'range loop
            r := r * 16 + hexchar_to_int(s(i));
        end loop;
        
        return r;
    end function;    
        
    impure function intel_hex_read(
        file_name      : in string;  -- Name of the IntelHex-File to initialize the memory
        mem_base       : in natural; -- Byte-Address, lower two bits should be zero
        mem_size       : in natural  -- in Bytes
    ) return mem_type is
        file input_file           : text;
        variable input_line       : line;
        variable colon            : character;
        variable byte_count       : integer;
        variable address          : unsigned(31 downto 0) := x"00000000";
        variable Extend           : unsigned(31 downto 0) := x"00000000";
        variable byte_s           : string(1 to 2);
        variable byte_i           : integer range 0 to 255;
        variable byte_u           : unsigned(7 downto 0);
        variable csum             : unsigned(7 downto 0);
        variable offset           : unsigned(31 downto 0);
        variable word             : std_logic_vector(31 downto 0);
        variable mem_values       : mem_type(0 to mem_size / 4 - 1) := mem_type'(0 to mem_size / 4 - 1 => (31 downto 0 =>'0'));
        variable line_number      : integer := 0;
        variable open_status      : FILE_OPEN_STATUS;
        variable eof_record_seen  : boolean := false;
        variable byte_index       : integer range 0 to 3;
        variable FLUSH_LINE       : boolean := false;

--      variable read_value       : string(1 to 100) := (others=>' ');
--      variable read_index       : integer := 1;
        
      begin
        assert mem_base mod mem_size = 0 report "Basisadresse des Speichers ist nicht Vielfaches seiner Groesse"  severity failure;
        assert mem_base mod 4 = 0        report "Basisadresse des Speichers ist nicht an Wortgrenze ausgerichtet" severity failure;
        
        if file_name="" then
          return mem_values; 
        else
          ----------------------------------------------------------------------------------------------------------------------
          -- Erster Durchlauf: "Extended Segment Address Record (Typ 04)" oder "Extended Linear Address Record (Typ 04)" finden
          ----------------------------------------------------------------------------------------------------------------------
          file_open(open_status, input_file, file_name, READ_MODE);      
          
          if not (open_status = OPEN_OK) then
              report "Hex-Datei '" & file_name & "' konnte nicht geoeffnet werden." severity error;
              return mem_values;
          end if;
          
          -- One loop iteration per line in the input file
          while not (endfile(input_file) or eof_record_seen) loop
              line_number := line_number + 1;
          
              csum := x"00"; -- initialize check sum
              readline(input_file, input_line);
              
              read(input_line, colon);
              
              if colon /= ':' then
                  report "Fehler in HEX-Datei " & file_name & " (Zeile " & integer'image(line_number) & "): Zeile beginnt nicht mit ':' sondern mit '" & colon &"'" severity warning;
                  exit;
              end if;
              
              -- read and process byte_count
              read(input_line, byte_s);
              byte_i     := hexstr_to_int(byte_s);
              byte_u     := to_unsigned(byte_i, 8);
              csum       := csum + byte_u;
              byte_count := byte_i;
              assert NO_DEBUG_OUTPUT report "byte_count:" & integer'image(byte_count) severity note; 
              
              -- read and process address
              read(input_line, byte_s);
              byte_i               := hexstr_to_int(byte_s);
              byte_u               := to_unsigned(byte_i, 8);
              csum                 := csum + byte_u;
              address(15 downto 8) := to_unsigned(byte_i, 8);
              
              read(input_line, byte_s);
              byte_i               := hexstr_to_int(byte_s);
              byte_u               := to_unsigned(byte_i, 8);
              csum                 := csum + byte_u;
              address(7 downto 0)  := to_unsigned(byte_i, 8);

              -- read and process record type
              read(input_line, byte_s);
              byte_i  := hexstr_to_int(byte_s);
              byte_u  := to_unsigned(byte_i, 8);
              csum    := csum + byte_u;
                  
              if byte_i = 16#00# then -- Data Record
                assert NO_DEBUG_OUTPUT report "Data Record" severity note;
                for i in 0 to byte_count - 1 loop
                    -- read two character string from file
                    read(input_line, byte_s);
                    byte_i  := hexstr_to_int(byte_s);
                    byte_u  := to_unsigned(byte_i, 8);
                    csum := csum + byte_u;
                end loop;
                  
              elsif byte_i = 16#01# then -- End of File Record
                assert NO_DEBUG_OUTPUT report "End of File Record" severity note;
                eof_record_seen := true;
 
              elsif address=0 and byte_i = 16#02# then -- Extended Segment Address
                assert NO_DEBUG_OUTPUT report "Extended Segment Address" severity note;
                -- The lower nibble is prepended to all addresses that follow this record.
                -- This allows addressing up to one megabyte of address space.
                
                -- read first address byte
                read(input_line, byte_s);
                byte_i                := hexstr_to_int(byte_s);
                byte_u                := to_unsigned(byte_i, 8);
                csum                  := csum + byte_u;
                Extend(31 downto 20)  := x"000";
                Extend(19 downto 12)  := byte_u;
                
                -- read second address byte
                read(input_line, byte_s);
                byte_i                := hexstr_to_int(byte_s);
                byte_u                := to_unsigned(byte_i, 8);
                csum                  := csum + byte_u;
                Extend(11 downto 4)   := byte_u;
                Extend( 3 downto 0)   := x"0"; 
                
              elsif byte_i = 16#03# then -- Start Segment Address (ignore)
                assert NO_DEBUG_OUTPUT report "Start Segment Address (ignore)" severity note;
                for i in 0 to byte_count - 1 loop
                  read(input_line, byte_s);
                  byte_i              := hexstr_to_int(byte_s);
                  byte_u              := to_unsigned(byte_i, 8);
                  csum                := csum + byte_u;
                end loop;
                   
              elsif address=0 and byte_i = 16#04# then -- Extended Linear Address
                assert NO_DEBUG_OUTPUT report "Extended Linear Address" severity note;
                read(input_line, byte_s);
                byte_i                := hexstr_to_int(byte_s);
                byte_u                := to_unsigned(byte_i, 8);
                csum                  := csum + byte_u;
                Extend(31 downto 24)  := byte_u;
                
                read(input_line, byte_s);
                byte_i                := hexstr_to_int(byte_s);
                byte_u                := to_unsigned(byte_i, 8);
                csum                  := csum + byte_u;
                Extend(23 downto 16)  := byte_u;
              
              elsif byte_i = 16#05# then -- Start Linear Address (ignore)
                assert NO_DEBUG_OUTPUT report "Start Linear Address (ignore)" severity note;
                for i in 0 to byte_count - 1 loop
                  read(input_line, byte_s);
                  byte_i               := hexstr_to_int(byte_s);
                  byte_u               := to_unsigned(byte_i, 8);
                  csum                 := csum + byte_u;
                end loop;

              else -- Unexpected Record
                report "Fehler in HEX-Datei (Zeile " & integer'image(line_number) & "): Dieser Record-Typ wird nicht unterstuetzt." severity failure;
                      
              end if;
                  
              -- Verify check sum
              read(input_line, byte_s);
              byte_i := hexstr_to_int(byte_s);
              byte_u := to_unsigned(byte_i, 8);
              csum   := csum + byte_u;
              assert csum = 0 
                 report "Fehler in HEX-Datei (Zeile " & integer'image(line_number) &
                        "): Die Pruefsumme ist falsch."
                 severity failure;
                      
          end loop;
          
          file_close(input_file);
          eof_record_seen := false; 

          ----------------------------------------------------------------------------------------------------------------------
          -- Zweiter Durchlauf: Speichermatrix mit Werten aus dem zugeordneten Adressfenster füllen
          ----------------------------------------------------------------------------------------------------------------------
          
          line_number := 0;
          
          file_open(open_status, input_file, file_name, READ_MODE);      
          
          if not (open_status = OPEN_OK) then
              report "Hex-Datei '" & file_name & "' konnte nicht geoeffnet werden." severity error;
              return mem_values;
          end if;
          
          -- One loop iteration per line in the input file
          while not (endfile(input_file) or eof_record_seen) loop
              FLUSH_LINE := false;
              line_number := line_number + 1;
          
              csum := x"00"; -- initialize check sum
              readline(input_file, input_line);
              
              read(input_line, colon);
              
              if colon /= ':' then
                  report "Fehler in HEX-Datei " & file_name & " (Zeile " & integer'image(line_number) & 
                         "): Zeile beginnt nicht mit ':' sondern mit '" & colon &"'"
                         severity warning;
                  exit;
              end if;
              
              -- read and process byte_count
              read(input_line, byte_s);
              byte_i     := hexstr_to_int(byte_s);
              byte_u     := to_unsigned(byte_i, 8);
              csum       := csum + byte_u;
              byte_count := byte_i;
              assert NO_DEBUG_OUTPUT report "byte_count:" & integer'image(byte_count) severity note; 
              
              -- read and process address
              read(input_line, byte_s);
              byte_i               := hexstr_to_int(byte_s);
              byte_u               := to_unsigned(byte_i, 8);
              csum                 := csum + byte_u;
              address(15 downto 8) := to_unsigned(byte_i, 8);
              
              read(input_line, byte_s);
              byte_i               := hexstr_to_int(byte_s);
              byte_u               := to_unsigned(byte_i, 8);
              csum                 := csum + byte_u;
              address(7 downto 0)  := to_unsigned(byte_i, 8);

              -- read and process record type
              read(input_line, byte_s);
              byte_i  := hexstr_to_int(byte_s);
              byte_u  := to_unsigned(byte_i, 8);
              csum    := csum + byte_u;
                  
              if byte_i = 16#00# then -- Data Record
                assert NO_DEBUG_OUTPUT report "Data Record" severity note;
                
                  -- Compute address offset in memory
                  offset := (Extend+address) - mem_base;  -- Byte offset to mem_base 
   
                  for i in 0 to byte_count - 1 loop

                      -- read two character string from file
                      read(input_line, byte_s);
                      assert NO_DEBUG_OUTPUT report "data(" & integer'image(i) & ")=0x" & byte_s severity note;
                      -- convert character string to it's unsigned value
                      byte_u := to_unsigned(hexstr_to_int(byte_s), 8);

                      -- Only Bytes with addresses in this memory's address range are processed
                      if (offset >= 0) and (offset < mem_size*4) then            
                          -- read old word
                          word := mem_values(to_integer(offset(31 downto 2)));
                          -- modify word
                          byte_index := to_integer(offset(1 downto 0));
                          word(8 * byte_index + 7 downto 8 * byte_index) := std_logic_vector(byte_u);

                          -- write modified word
                          mem_values(to_integer(signed(offset(31 downto 2)))) := word;
                      else
                        report "Speicherinhalt in Zeile " & integer'image(line_number) &
                               "  der IntelHEX-Datei liegt nicht im Adressfenster des Speichers"
                          severity warning;
                        FLUSH_LINE := true;
                        exit;
                      end if;              
                      csum  := csum + byte_u;              
                      offset := offset + 1;  
                  end loop;
                  assert NO_DEBUG_OUTPUT report "End Loop" severity note;
                  
              elsif byte_i = 16#01# then -- End of File Record
                assert NO_DEBUG_OUTPUT report "End of File Record" severity note;
                eof_record_seen := true;

              elsif byte_i = 16#02# then -- Extended Segment Address
                assert NO_DEBUG_OUTPUT report "Extended Segment Address" severity note;
                -- read first address byte
                read(input_line, byte_s);
                byte_u := to_unsigned(hexstr_to_int(byte_s), 8);
                csum                  := csum + byte_u;
                -- read second address byte
                read(input_line, byte_s);
                byte_u := to_unsigned(hexstr_to_int(byte_s), 8);
                csum                  := csum + byte_u;
                
              elsif byte_i = 16#03# then -- Start Segment Address (ignore)
                assert NO_DEBUG_OUTPUT report "Start Segment Address (ignore)" severity note;
                for i in 0 to byte_count - 1 loop
                  read(input_line, byte_s);
                  byte_u := to_unsigned(hexstr_to_int(byte_s), 8);
                  csum                := csum + byte_u;
                end loop;
                   
              elsif byte_i = 16#04# then -- Extended Linear Address
                assert NO_DEBUG_OUTPUT report "Extended Linear Address" severity note;
                read(input_line, byte_s);
                byte_u := to_unsigned(hexstr_to_int(byte_s), 8);
                csum                  := csum + byte_u;
                read(input_line, byte_s);
                byte_u := to_unsigned(hexstr_to_int(byte_s), 8);
                csum                  := csum + byte_u;
              
              elsif byte_i = 16#05# then -- Start Linear Address (ignore)
                assert NO_DEBUG_OUTPUT report "Start Linear Address (ignore)" severity note;
                for i in 0 to byte_count - 1 loop
                  read(input_line, byte_s);
                  byte_u := to_unsigned(hexstr_to_int(byte_s), 8);
                  csum                 := csum + byte_u;
                end loop;

              else -- Unexpected Record
                report "Fehler in HEX-Datei (Zeile " & integer'image(line_number) & "): Dieser Record-Typ wird nicht unterstuetzt." severity failure;
                      
              end if;
                  
              -- Verify check sum
              read(input_line, byte_s);
--            read_value(read_index to read_index+1) := byte_s; read_index := read_index+2;
              byte_i := hexstr_to_int(byte_s);
              byte_u := to_unsigned(byte_i, 8);
              csum   := csum + byte_u;
              assert csum = 0 or FLUSH_LINE = true
                 report "Fehler in HEX-Datei (Zeile " & integer'image(line_number) &
                        "): Die Pruefsumme ist falsch."
                 severity failure;

--            assert NO_DEBUG_OUTPUT report "read_value: "&read_value severity note; 
                      
          end loop;
          
          file_close(input_file);
          
        end if;
        return mem_values;
    end function;

    impure function extract_bytelane(
      bytelane:    in natural;
      mem_content: in mem_type
    ) return byte_mem_type is
        variable byte_mem_values : byte_mem_type(mem_content'range) := (others=>x"00");
    begin
      if (bytelane>=0) and (bytelane <=3) then
        for i in mem_content'range loop
          byte_mem_values(i) := mem_content(i)(8*bytelane+7 downto 8*bytelane);
        end loop;
      else
        report "intel_hex_pack->extract_bytelane: wrong bytelane selected" severity error;
      end if;
      return byte_mem_values;
    end function;

    impure function extract_halflane(
      halflane:    in natural;
      mem_content: in mem_type
    ) return half_mem_type is
        variable half_mem_values : half_mem_type(mem_content'range) := (others=>x"0000");
    begin
      if (halflane>=0) and (halflane <=1) then
        for i in mem_content'range loop
          half_mem_values(i) := mem_content(i)(16*halflane+15 downto 16*halflane);
        end loop;
      else
        report "intel_hex_pack->extract_halflane: wrong halflane selected" severity error;
      end if;
      return half_mem_values;
    end function;

end package body;