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

---------------------------------------------------------------------------------------------------
-- UART fuer Beispielrechner
-- Bernhard Lang, Rainer Hoeckmann
-- (c) Hochschule Osnabrueck
---------------------------------------------------------------------------------------------------
-- Register:
-- 0x00 Transmit Data Register (TDR)
-- 0x04 Receive Data Register (RDR)
-- 0x08 Control Register (CR)
-- 0x0C Status Register (SR)
---------------------------------------------------------------------------------------------------
-- Control Register (CR):
--  15..0  : Bitbreite - 1
--  19..16 : Anzahl Datenbits - 1
--  20     : Paritaet ein
--  21     : Paritaet gerade
--  23..22 : Stopbits 
--           0: 1.0 Stoppbits
--           1: 1.5 Stoppbits
--           2: 2.0 Stoppbits
--           3: 2.5 Stoppbits
--  24     : Freigabe Rx Interrupt
--  25     : Freigabe Tx Interrupt
---------------------------------------------------------------------------------------------------
-- Status Register (SR):
--  0      : Puffer_Valid
--  1      : Sender_Ready
--  2      : Ueberlauf (wird beim Lesen geloescht)
--  24     : Rx_IRQ
--  25     : Tx_IRQ
---------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity UART is
  port (
    -- Wishbone Bus
    CLK_I              : in  std_logic;
    RST_I              : in  std_logic;
    STB_I              : in  std_logic;
    WE_I               : in  std_logic;
    ADR_I              : in  std_logic_vector(3 downto 2);
    DAT_I              : in  std_logic_vector(31 downto 0);
    DAT_O              : out std_logic_vector(31 downto 0);
    ACK_O              : out std_logic;
    -- Interupt
    Interrupt          : out std_logic;
    -- Port Pins
    RxD                : in  std_logic;
    TxD                : out std_logic
  );
end UART;

architecture behavioral of UART is
  constant DATA_WIDTH        : positive := 16;
  constant BITBREITE_WIDTH   : positive := 16;
  constant BITS_WIDTH        : positive := 4;

  signal Kontroll            : std_logic_vector(31 downto 0) := (others=>'0');
  signal Status              : std_logic_vector(31 downto 0) := (others=>'0');
  signal Ueberlauf           : std_logic                     := '0';

  signal Schreibe_Daten      : std_logic;
  signal Schreibe_Kontroll   : std_logic;
  signal Lese_Status         : std_logic;

  signal BitBreiteM1         : std_logic_vector(BITBREITE_WIDTH - 1 downto 0);
  signal BitsM1              : std_logic_vector(BITS_WIDTH - 1 downto 0);
  signal Paritaet_ein        : std_logic;
  signal Paritaet_gerade     : std_logic;
  signal Stoppbits           : std_logic_vector(1 downto 0);  
  signal Rx_IrEn             : std_logic;
  signal Tx_IrEn             : std_logic;
  signal Rx_Interrupt        : std_logic;
  signal Tx_Interrupt        : std_logic;

  signal Sender_Ready        : std_logic;

  signal Empfaenger_Valid    : std_logic;
  signal Empfaenger_Ready    : std_logic;
  signal Empfaenger_Data     : std_logic_vector(15 downto 0);

  signal Puffer_Valid        : std_logic := '0';
  signal Puffer_Ready        : std_logic := '-';
  signal Puffer_Data         : std_logic_vector(15 downto 0) := (others => '-');

begin
  ACK_O              <= STB_I;
  Interrupt          <= Tx_Interrupt or Rx_Interrupt;
  Tx_Interrupt       <= Tx_IrEn and Sender_Ready;
  Rx_Interrupt       <= Rx_IrEn and Puffer_Valid;

  -- Statusregister mit Statussignalen verbinden
  process(Puffer_Valid, Sender_Ready, Ueberlauf, Rx_Interrupt, Tx_Interrupt)
  begin
    Status <= (Status'range => '0');
    Status( 0) <= Puffer_Valid;
    Status( 1) <= Sender_Ready;
    Status( 2) <= Ueberlauf;
    Status(24) <= Rx_Interrupt;
    Status(25) <= Tx_Interrupt;
  end process;
  
    -- Kontrollregister mit Steuersignalen verbinden
  BitBreiteM1     <= std_logic_vector(Kontroll(15 downto 0));
  BitsM1          <= std_logic_vector(Kontroll(19 downto 16));
  Paritaet_ein    <= Kontroll(20);
  Paritaet_gerade <= Kontroll(21);
  Stoppbits       <= std_logic_vector(Kontroll(23 downto 22));
  Rx_IrEn         <= Kontroll(24);
  Tx_IrEn         <= Kontroll(25);

  Decoder: process(STB_I, ADR_I, WE_I)
  begin
    -- Default-Werte
    Schreibe_Kontroll <= '0';
    Schreibe_Daten    <= '0';
    Puffer_Ready      <= '0';
    Lese_Status       <= '0';

    if STB_I = '1' then
      if WE_I = '1' then
        if    ADR_I = "00" then Schreibe_Daten    <= '1';
        elsif ADR_I = "10" then Schreibe_Kontroll <= '1';
        end if;
      elsif WE_I = '0' then
        if    ADR_I = "01" then Puffer_Ready      <= '1';
        elsif ADR_I = "11" then Lese_Status       <= '1';
        end if;
      end if;   
    end if;
  end process;

  Lesedaten_MUX: process(ADR_I, Puffer_Data, Kontroll, Status)
  begin
    DAT_O <= (others=>'0');
    if    ADR_I = "01" then DAT_O(Puffer_Data'range) <= Puffer_Data;
    elsif ADR_I = "10" then DAT_O(Kontroll'range)    <= Kontroll;
    elsif ADR_I = "11" then DAT_O(Status'range)      <= Status;
    end if;   
  end process;

  -- Kontrollregister
  Regs: process(CLK_I)
  begin
    if rising_edge(CLK_I) then
      if RST_I = '1' then
        Kontroll <= x"00"&"00"&"00"&x"7"&x"0018" ; -- 1 Stoppbit, keine Paritaet, 8 Datenbits, (2 MBaud)@50MHz
      elsif Schreibe_Kontroll = '1' then
        Kontroll <= DAT_I;
      end if;
    end if;
  end process;
  
  -- Ueberlauferkennung
  OverflowReg: process(CLK_I)
  begin
    if rising_edge(CLK_I) then  
      if RST_I = '1' then
        Ueberlauf <= '0';
      else
        -- Beim Lesen von Status zuruecksetzen
        if Lese_Status = '1' then
          Ueberlauf <= '0';
        end if;
        -- Setzen bei erkanntem Ueberlauf
        if Empfaenger_Valid = '1' and Empfaenger_Ready = '0' then
          Ueberlauf <= '1';
        end if;       
      end if;
    end if;
  end process;

  -- Fifo fuer Empfangene Daten
  PufferFifo: entity work.DS_Fifo
    generic  map ( 
      DataSize    => 16, 
      AddressSize => 5
    )
    port map (
      -- commons
      Clock     => CLK_I,            -- clock
      Reset     => RST_I,            -- synchronous reset
      -- input side
      valid_in  => Empfaenger_Valid, -- valid control input for data_in
      data_in   => Empfaenger_Data,  -- Data input
      ready_in  => Empfaenger_Ready, -- ready to input
      -- output side
      valid_out => Puffer_Valid,     -- valid control output for data_out
      data_out  => Puffer_Data,      -- Data output
      ready_out => Puffer_Ready      -- ready from output
    );  
    
--  -- DataSync fuer Empfangene Daten
--  DataSyncReg: block
--  begin
--    --
--    process(CLK_I)
--    begin
--      if rising_edge(CLK_I) then
--        if RST_I = '1' then
--          Puffer_Valid <= '0';
--          Puffer_Data  <= (others=>'0');
--        else      
--          if Empfaenger_Ready = '1' then
--            Puffer_Valid <= Empfaenger_Valid;
--            Puffer_Data  <= Empfaenger_Data;
--          end if;         
--        end if;       
--      end if;
--    end process;
--    --
--    Empfaenger_Ready <= (not Puffer_Valid) or Puffer_Ready;
--    --
--  end block;

  Empfaenger: entity work.Serieller_Empfaenger
  generic map(
    DATA_WIDTH      => DATA_WIDTH,
    BITBREITE_WIDTH => BITBREITE_WIDTH,
    BITS_WIDTH      => BITS_WIDTH
  ) port map(
    Takt            => CLK_I,
    Reset           => RST_I,
    BitBreiteM1     => BitBreiteM1,
    BitsM1          => BitsM1,
    Paritaet_ein    => Paritaet_ein,
    Paritaet_gerade => Paritaet_gerade,
    Stoppbits       => Stoppbits,
    M_Valid         => Empfaenger_Valid,
    M_Data          => Empfaenger_Data,
    RxD             => RxD
  );

  Sender: entity work.Serieller_Sender
  generic map(
    DATA_WIDTH      => DATA_WIDTH,
    BITBREITE_WIDTH => BITBREITE_WIDTH,
    BITS_WIDTH      => BITS_WIDTH
  ) port map(
    Takt            => CLK_I,
    Reset           => RST_I,
    BitBreiteM1     => BitBreiteM1,
    BitsM1          => BitsM1,
    Paritaet_ein    => Paritaet_ein,
    Paritaet_gerade => Paritaet_gerade,
    Stoppbits       => Stoppbits,
    S_Valid         => Schreibe_Daten,
    S_Ready         => Sender_Ready,
    S_Data          => DAT_I(DATA_WIDTH - 1 downto 0),
    TxD             => TxD
  );

end behavioral;

