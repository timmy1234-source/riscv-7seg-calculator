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

-------------------------------------------------------------------------------
-- Serieller Empfaenger
-------------------------------------------------------------------------------
-- Modul Digitale Komponenten
-- Hochschule Osnabrueck
-- Bernhard Lang, Rainer Hoeckmann
-------------------------------------------------------------------------------
-- BitBreiteM1 = (Taktfrequenz / Baudrate) - 1
--
-- Bits = AnzahlBits - 1
--
-- Kodierung Stoppbits:
--   00 - 1   Stoppbits
--   01 - 1,5 Stobbits
--   10 - 2   Stoppbits
--   11 - 2,5 Stoppbits
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Serieller_Empfaenger is
  generic(
    DATA_WIDTH      : positive;
    BITBREITE_WIDTH : positive;
    BITS_WIDTH      : positive
  );  
  port( 
    Takt            : in  std_logic;
    Reset           : in  std_logic;
    BitBreiteM1     : in  std_logic_vector(BITBREITE_WIDTH - 1 downto 0);
    BitsM1          : in  std_logic_vector(BITS_WIDTH - 1 downto 0);
    Paritaet_ein    : in  std_logic;
    Paritaet_gerade : in  std_logic;
    Stoppbits       : in  std_logic_vector(1 downto 0);
    M_Valid         : out std_logic;
    M_Data          : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    RxD             : in  std_logic
  );
end entity;

architecture rtl of Serieller_Empfaenger is 
  
  -- Signale zwischen Steuerwerk und Rechenwerk
  signal DataLd    : std_logic;
  signal DataR     : std_logic;
  signal CntSel    : std_logic := '-';
  signal CntEn     : std_logic;
  signal CntLd     : std_logic;
  signal CntTc     : std_logic := '1';
  signal BBSel     : std_logic := '0';
  signal BBLd      : std_logic;
  signal BBTC      : std_logic := '0';
  signal P_ok      : std_logic;
    
  signal RxD_sync0 : std_logic := '1';
  signal RxD_sync1 : std_logic := '1';
  
begin
    process(Takt)
    begin
        if rising_edge(Takt) then
            RxD_sync0 <= RxD;
            RxD_sync1 <= RxD_sync0;
        end if;
    end process;

  Rechenwerk: block
  
      -- Interne Signale des Rechenwerks
    signal DataBit    : std_logic := '0';
    signal ParityBit  : std_logic := '0';
    signal M_Data_i   : std_logic_vector(M_Data'range) := (others=>'0');
    signal BitsLeft   : unsigned(BITS_WIDTH - 1 downto 0);
    
  begin
    M_Data <= M_Data_i;
  
    -- Register zur Aufnahme der empfangenen Daten
    Datenregister: process(Takt)
      variable Q : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others=>'0');
      variable i : integer range 0 to DATA_WIDTH - 1;
    begin
      if rising_edge(Takt) then
        if Reset = '1' then
          Q := (others=>'0');
        else
          if DataR = '1' then
            Q := (others=>'0');
          elsif DataLd = '1' then
            i := to_integer(unsigned(BitsM1)) - to_integer(BitsLeft);
            Q(i) := RxD_sync1;          
          end if;
        end if;
        M_Data_i <= Q;              
      end if;     
    end process;
    
    -- Berechnung des Paritaetsbits
    Par: process(M_Data_i, RxD_sync1, Paritaet_gerade)
      variable p : std_logic := '0';
    begin 
      p := Paritaet_gerade;
      for i in M_Data_i'range loop
        p := p xor M_Data_i(i);
      end loop;
      P_ok <= p or RxD_sync1;     
    end process;
    
    -- Zaehler Bits und Stoppbits
    ZaehlerBits: process(Takt)
      variable Q : unsigned(BITS_WIDTH - 1 downto 0) := (others=>'0');
    begin
      if rising_edge(Takt) then
        if Reset = '1' then
          Q := (others=>'0');
        else
          if CntLd = '1' then
            if CntSel = '0' then
              Q := unsigned(BitsM1);
            elsif CntSel = '1' then
              Q(BITS_WIDTH - 1 downto Stoppbits'High + 1) := (others=>'0');
              Q(Stoppbits'High downto Stoppbits'Low)      := unsigned(Stoppbits);
            end if;
          elsif CntEn = '1' then
            Q := Q - 1;
          end if;
        end if;
        if Q = 0 then 
          CntTc <= '1';
        else 
          CntTc <= '0'; 
        end if;           
        BitsLeft <= Q;
      end if;
    end process;
    
    -- Zaehler Bitbreite
    ZaehlerBitbreite: process(Takt)
      variable Q : unsigned(BITBREITE_WIDTH - 1 downto 0) := (others=>'0');
    begin
      if rising_edge(Takt) then
        if Reset = '1' then
          Q := (others=>'0');
        else
          if BBLd = '1' or BBTC = '1' then
            if BBSel = '0' then
              Q := unsigned(BitBreiteM1);
            elsif BBSel = '1' then
              Q := unsigned('0' & BitBreiteM1(BITBREITE_WIDTH - 1 downto 1));
            end if;
          else
            Q := Q - 1;
          end if;
        end if;
        if Q = 0 then 
          BBTC <= '1';
        else 
          BBTC <= '0'; 
        end if;       
      end if;
    end process;
    
  end block;
  
  Steuerwerk: block
  
    -- Typ fuer die Zustandswerte
    type Zustand_type is (Z_IDLE, Z_START, Z_BITS, Z_PARI, Z_STP, Z_RDY, Z_FRERR, Z_PAERR, Z_ERROR);

      -- Interne Signale des Rechenwerks
    signal Zustand      : Zustand_type := Z_IDLE;
    signal Folgezustand : Zustand_type;   
    
    -- Internes Signal fuer die Initialisierung
    signal M_Valid_i    : std_logic := '0';
    
  begin        
    -- Wert des internen Signals an Port zuweisen 
    M_Valid <= M_Valid_i;

    -- Prozess zur Berechnung des Folgezustands und der Mealy-Ausgaenge
    Transition: process(Zustand, BBTC, CntTC, Paritaet_ein, P_ok, RxD_sync1)
    begin
      -- Default-Werte fuer den Folgezustand und die Mealy-Ausgaenge
      DataLd       <= '0'; 
      DataR        <= '0'; 
      CntEn        <= '0'; 
      CntLd        <= '0'; 
      BBLd         <= '0';
      Folgezustand <= Z_ERROR;
      -- Berechnung des Folgezustands und der Mealy-Ausgaenge
      case Zustand is
        when Z_IDLE  =>
          if RxD_sync1 = '1' then 
            Folgezustand <= Z_IDLE;
          elsif RxD_sync1 = '0' then 
            Folgezustand <= Z_START; 
            BBLd <= '1';
          end if;
        when Z_START =>
          if BBTC = '0' then 
            Folgezustand <= Z_START;
          elsif BBTC = '1' then
            if RxD_sync1 = '0' then 
              Folgezustand <= Z_BITS; 
              CntLd <= '1'; 
              BBLd <= '1'; 
              DataR <= '1';
            elsif RxD_sync1 = '1' then 
              Folgezustand <= Z_FRERR;
            end if;
          end if;
        when Z_BITS =>
          if BBTC = '0' then 
            Folgezustand <= Z_BITS;
          elsif BBTC = '1' then
            DataLd <= '1'; 
            BBLd <= '1';
            if CntTC = '0' then 
              Folgezustand <= Z_BITS; 
              CntEn <= '1';
            elsif CntTC = '1' then
              if Paritaet_ein = '1' then 
                Folgezustand <= Z_PARI; 
              elsif Paritaet_ein = '0' then
                Folgezustand <= Z_STP;
                CntLd <= '1';
              end if;
            end if;
          end if;
        when Z_PARI =>
          if BBTC = '0' then
            Folgezustand <= Z_PARI;
          elsif BBTC = '1' then
            if P_ok = '1' then
              Folgezustand <= Z_STP;
              CntLd <= '1';
              BBLd <= '1';
            elsif P_ok = '0' then
              Folgezustand <= Z_PAERR;
            end if;
          end if;
        when Z_STP =>
          if BBTC = '0' then
            Folgezustand <= Z_STP;
          elsif BBTC = '1' then
            if RxD_sync1 = '0' then
              Folgezustand <= Z_FRERR;
            elsif RxD_sync1 = '1' then
              if CntTC = '0' then
                Folgezustand <= Z_STP;
                CntEn <= '1';
              elsif CntTC = '1' then
                Folgezustand <= Z_RDY;
              end if;
            end if;
          end if;
        when Z_RDY =>
          Folgezustand <= Z_IDLE;
        when Z_FRERR =>
          -- synthesis translate off
          report "Serieller_Empfaenger: Frame Error" severity error;
          -- synthesis translate on
          Folgezustand <= Z_IDLE;
        when Z_PAERR =>
          -- synthesis translate off
          report "Serieller_Empfaenger: Parity Error" severity error;
          -- synthesis translate on
          Folgezustand <= Z_IDLE;
        when Z_ERROR =>
          -- synthesis translate off
          report "Serieller_Empfaenger erreicht Fehlerzustand" severity error;
          -- synthesis translate on
          Folgezustand <= Z_IDLE;
      end case;
    end process;
    
    -- Register fuer Zustand und Moore-Ausgaenge
    Reg: process(Takt)
    begin
      if rising_edge(Takt) then
        -- Zustandsregister
        if Reset = '1' then
          Zustand <= Z_IDLE;
        else
          Zustand <= Folgezustand;
        end if;
        -- Berechnung der Moore-Ausgaenge aus dem Folgezustand
        if Reset = '1' then
          M_Valid_i <= '0'; CntSel <= '-'; BBSel <= '1';
        else
          case Folgezustand is
            when Z_IDLE  => M_Valid_i <= '0'; CntSel <= '-'; BBSel <= '1';
            when Z_START => M_Valid_i <= '0'; CntSel <= '0'; BBSel <= '0';
            when Z_BITS  => M_Valid_i <= '0'; CntSel <= '1'; BBSel <= '0';
            when Z_PARI  => M_Valid_i <= '0'; CntSel <= '1'; BBSel <= '0';
            when Z_STP   => M_Valid_i <= '0'; CntSel <= '-'; BBSel <= '1';
            when Z_RDY   => M_Valid_i <= '1'; CntSel <= '-'; BBSel <= '-';
            when Z_FrErr => M_Valid_i <= '0'; CntSel <= '-'; BBSel <= '-';
            when Z_PaErr => M_Valid_i <= '0'; CntSel <= '-'; BBSel <= '-';
            when Z_ERROR => M_Valid_i <= '0'; CntSel <= '-'; BBSel <= '-';
          end case;
        end if;
      end if;
    end process;
      
  end block;
end architecture;