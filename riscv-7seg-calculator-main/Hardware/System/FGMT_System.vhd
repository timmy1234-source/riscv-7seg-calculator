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
--use work.FGMT_pack.all;
entity FGMT_System is
  generic (
    Frequency           : integer := 50_000_000;
    ADR_WIDTH           : integer := 16;
    THREAD_NO_WIDTH     : integer :=  3;
    ERR_ID_WIDTH        : integer :=  2;
    TH_ACTIVITY_TIMEOUT : integer := 15;
    HEX_FILE            : string  :=  "../../Software_Leer.hex" -- "../System/Memory/Software_Leer.hex"
  );
  port (
    CLK        : in    std_logic;
    RESET      : in    std_logic;
    -- Diagnostic outputs
    ActThreads : out   std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    ThActivity : out   std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    ErrVect    : out   std_logic_vector(31 downto 0);
    AxsVect    : out   std_logic_vector(31 downto 0);
    -- External WB Master Port
    GDB_RxD    : in    std_logic;
    GDB_TxD    : out   std_logic;
    -- IOs
    PINS       : inout std_logic_vector(24 downto 0);
    --
    PWM        : out   std_logic;
    --
    RxD        : in    std_logic;
    TxD        : out   std_logic
  );
  ------------------------------------------------------------
  -- Start address and number of starting thread
  ------------------------------------------------------------
  constant Startaddress   : integer := 0;
  constant StartThread    : integer := 0;
  ------------------------------------------------------------
  --Address Map
  ------------------------------------------------------------
  constant EXT_WB_BASE     : unsigned(31 downto 0) := x"FFFFFE00"; -- Start of internal wishbone bus peripherals
  constant EXT_WB_ldSize   : natural := 8;                         -- Internal peripherals occupy 2**8 bytes of address space
  constant GPIO_BASE       : unsigned(31 downto 0) := x"FFFFFEC0";
  constant GPIO_ldSize     : integer               := 5;
  constant TIMER_BASE      : unsigned(31 downto 0) := x"FFFFFEE0";
  constant TIMER_ldSize    : integer               := 5;
  constant UART_BASE       : unsigned(31 downto 0) := x"FFFFFEB0";
  constant UART_ldSize     : integer               := 4;
  constant INTERRUPT_COUNT : integer               := 3;
end FGMT_System;

architecture arch of FGMT_System is
  signal Interrupts : std_logic_vector(INTERRUPT_COUNT-1 downto 0);
  -- IBUS --
  -- IBUS: Stream to Instruction Memory: Address Stream
  signal IA_Valid   : std_logic;
  signal IA_Ready   : std_logic;
  signal IA_ADR     : std_logic_vector(ADR_WIDTH-1 downto 1);
  signal IA_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- IBUS Stream from Instruction Memory: Data Stream
  signal IR_Valid   : std_logic;
  signal IR_Ready   : std_logic;
  signal IR_Inst    : std_logic_vector(31 downto 0);
  -- DBUS --
  -- DBUS: Data Memory Write stream
  signal DW_Valid   : std_logic;
  signal DW_Ready   : std_logic;
  signal DW_ADR     : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal DW_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal DW_DAT     : std_logic_vector(31 downto 0);
  signal DW_SEL     : std_logic_vector(3 downto 0);
  -- DBUS: Data Memory Read Address stream
  signal DRA_Valid  : std_logic;
  signal DRA_Ready  : std_logic;
  signal DRA_ADR    : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal DRA_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- DBUS: Data Memory Read Response stream
  signal DRR_Valid  : std_logic;
  signal DRR_Ready  : std_logic;
  signal DRR_DAT    : std_logic_vector(31 downto 0);
  -- WB_BUS --
  -- WB_BUS: Data Memory Write stream
  signal WBW_Valid   : std_logic;
  signal WBW_Ready   : std_logic;
  signal WBW_ADR     : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal WBW_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal WBW_DAT     : std_logic_vector(31 downto 0);
  signal WBW_SEL     : std_logic_vector(3 downto 0);
  -- WB_BUS: Data Memory Read Address stream
  signal WBRA_Valid  : std_logic;
  signal WBRA_Ready  : std_logic;
  signal WBRA_ADR    : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal WBRA_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- WB_BUS: Data Memory Read Response stream
  signal WBRR_Valid  : std_logic;
  signal WBRR_Ready  : std_logic;
  signal WBRR_DAT    : std_logic_vector(31 downto 0);
  -- Sysmem --
  -- Sysmem: Data Memory Write stream
  signal SMW_Valid   : std_logic;
  signal SMW_Ready   : std_logic;
  signal SMW_ADR     : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal SMW_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal SMW_DAT     : std_logic_vector(31 downto 0);
  signal SMW_SEL     : std_logic_vector(3 downto 0);
  -- Sysmem: Data Memory Read Address stream
  signal SMRA_Valid  : std_logic;
  signal SMRA_Ready  : std_logic;
  signal SMRA_ADR    : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal SMRA_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Sysmem: Data Memory Read Response stream
  signal SMRR_Valid  : std_logic;
  signal SMRR_Ready  : std_logic;
  signal SMRR_DAT    : std_logic_vector(31 downto 0);

begin

  FGMT_processor: entity work.FGMT_Processor
    generic map (
      Frequency           => Frequency,
      ADR_WIDTH           => ADR_WIDTH,
      THREAD_NO_WIDTH     => THREAD_NO_WIDTH,
      TH_ACTIVITY_TIMEOUT => TH_ACTIVITY_TIMEOUT,
      INTERRUPT_COUNT     => INTERRUPT_COUNT,
      Startaddress        => Startaddress,
      StartThread         => StartThread 
    )
    port map (
      CLK        => CLK,
      RESET      => RESET,
      -- Serial Debugger Port
      GDB_RxD    => GDB_RxD,
      GDB_TxD    => GDB_TxD,
      -- Interrupts
      Interrupts => Interrupts,
      -- Info outputs
      ActThreads => ActThreads,
      ThActivity => ThActivity,
      ErrVect    => ErrVect,
      AxsVect    => AxsVect,
      -- IBUS --
      -- IBUS: Stream to Instruction Memory: Address Stream
      MI_Valid   => IA_Valid,
      MI_Ready   => IA_Ready,
      MI_ADR     => IA_ADR,
      MI_ThNo    => IA_ThNo,
      -- IBUS Stream from Instruction Memory: Data Stream
      SI_Valid   => IR_Valid,
      SI_Ready   => IR_Ready,
      SI_Inst    => IR_Inst,
      -- DBUS --
      -- DBUS: Data Memory Write stream
      MW_Valid   => DW_Valid,
      MW_Ready   => DW_Ready,
      MW_ADR     => DW_ADR,
      MW_ThNo    => DW_ThNo,
      MW_DAT     => DW_DAT,
      MW_SEL     => DW_SEL,
      -- DBUS: Data Memory Read Address stream
      MR_Valid   => DRA_Valid,
      MR_Ready   => DRA_Ready,
      MR_ADR     => DRA_ADR,
      MR_ThNo    => DRA_ThNo,
      -- DBUS: Data Memory Read Response stream
      SR_Valid   => DRR_Valid,
      SR_Ready   => DRR_Ready,
      SR_DAT     => DRR_DAT
    );

  INTERCONN: entity work.Interconnect
    generic map (
      ADDR_WIDTH      => ADR_WIDTH,
      ADR0_BASE       => EXT_WB_BASE,      -- Processor external peripherals, base
      ADR0_SIZE       => 2**EXT_WB_ldSize, -- Processor external peripherals, size
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK       => CLK,
      RESET     => RESET,
      -- DBUS: Data Memory Read Address stream
      SR_Valid  => DRA_Valid,
      SR_Ready  => DRA_Ready,
      SR_ADR    => DRA_ADR,
      SR_ThNo   => DRA_ThNo,
      -- DBUS: Data Memory Read Response stream
      MR_Valid  => DRR_Valid,
      MR_Ready  => DRR_Ready,
      MR_DAT    => DRR_DAT,
      -- Read Request Output 0, to wishbone bridge
      MR0_Valid => WBRA_Valid,
      MR0_Ready => WBRA_Ready,
      MR0_ADR   => WBRA_ADR,
      MR0_ThNo  => WBRA_ThNo,
      -- Read Response Input 0, from wishbone bridge
      SR0_Valid => WBRR_Valid,
      SR0_Ready => WBRR_Ready,
      SR0_DAT   => WBRR_DAT,
      -- Read Request Output 1, to memory
      MR1_Valid => SMRA_Valid,
      MR1_Ready => SMRA_Ready,
      MR1_ADR   => SMRA_ADR,
      MR1_ThNo  => SMRA_ThNo,
      -- Read Response Input 1, from memory
      SR1_Valid => SMRR_Valid,
      SR1_Ready => SMRR_Ready,
      SR1_DAT   => SMRR_DAT,
      -- DBUS: Data Memory Write stream
      SW_Valid  => DW_Valid,
      SW_Ready  => DW_Ready,
      SW_DAT    => DW_DAT,
      SW_SEL    => DW_SEL,
      SW_ADR    => DW_ADR,
      SW_ThNo   => DW_ThNo,
      -- Write Request Output 0, to wishbone bridge
      MW0_Valid => WBW_Valid,
      MW0_Ready => WBW_Ready,
      MW0_DAT   => WBW_DAT,
      MW0_SEL   => WBW_SEL,
      MW0_ADR   => WBW_ADR,
      MW0_ThNo  => WBW_ThNo,
      -- Write Request Output 1, to memory
      MW1_Valid => SMW_Valid,
      MW1_Ready => SMW_Ready,
      MW1_DAT   => SMW_DAT,
      MW1_SEL   => SMW_SEL,
      MW1_ADR   => SMW_ADR,
      MW1_ThNo  => SMW_ThNo
    );

  Mem_block_16: block
    signal S1R_ADR : std_logic_vector(ADR_WIDTH-2 downto 1);
  begin
    S1R_ADR(ADR_WIDTH-2 downto 2) <= SMRA_ADR(ADR_WIDTH-2 downto 2);
    S1R_ADR(1) <= '0';
    MEM_inst: entity work.Memory_Read_Simple_Write_16AR
      generic map (
        MEM_ldSIZE    => ADR_WIDTH-1,
        BASE_ADDR     => 0,
        HEX_FILE_NAME => HEX_FILE
      )
      port map (
        CLK       => CLK,
        RESET     => RESET,
        -- Read Request from Instruction Port
        S0R_Valid => IA_Valid,
        S0R_Ready => IA_Ready,
        S0R_ADR   => IA_ADR(ADR_WIDTH-2 downto 1),
        -- Read Response to Instruction Port
        M0R_Valid => IR_Valid,
        M0R_Ready => IR_Ready,
        M0R_DAT   => IR_Inst,
        -- Read Request from Data Port
        S1R_Valid => SMRA_Valid,
        S1R_Ready => SMRA_Ready,
        S1R_ADR   => S1R_ADR,
        -- Read Response to Data Port
        M1R_Valid => SMRR_Valid,
        M1R_Ready => SMRR_Ready,
        M1R_DAT   => SMRR_DAT,
        -- Write Request from Data Port
        SW_Valid  => SMW_Valid,
        SW_Ready  => SMW_Ready,
        SW_ADR    => SMW_ADR(ADR_WIDTH-2 downto 2),
        SW_SEL    => SMW_SEL,
        SW_DAT    => SMW_DAT
      );
  end block;

  Wishbone: block
    -- Wishbone Bus
    signal WB_STB     : std_logic;
    signal WB_WE      : std_logic;
    signal WB_SEL     : std_logic_vector( 3 downto 0);
    signal WB_ADR     : std_logic_vector(ADR_WIDTH-1 downto 2);
    signal WB_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal WB_MOSI    : std_logic_vector(31 downto 0);
    signal WB_MISO    : std_logic_vector(31 downto 0);
    signal WB_ACK     : std_logic;
    -- GPIO 
    signal GPIO_STB   : std_logic;
    signal GPIO_ACK   : std_logic;
    signal GPIO_MISO  : std_logic_vector(31 downto 0);
    signal GPIO_IR    : std_logic;
    -- Timer 
    signal Timer_STB  : std_logic;
    signal Timer_ACK  : std_logic;
    signal Timer_MISO : std_logic_vector(31 downto 0);
    signal Timer_IR   : std_logic;
    -- UART 
    signal UART_STB   : std_logic;
    signal UART_ACK   : std_logic;
    signal UART_MISO  : std_logic_vector(31 downto 0);
    signal UART_IR    : std_logic;
  begin
    SYSWBB: entity work.WB_Bridge
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH,
        SR_ReadySync    => true,
        SR_DataSync     => true,
        MR_ReadySync    => true,
        MR_DataSync     => true
      )
      port map (
        CLK      => CLK,
        RESET    => RESET,
        -- AxiS Write Request
        SW_Valid => WBW_Valid,
        SW_Ready => WBW_Ready,
        SW_ADR   => WBW_ADR,
        SW_ThNo  => WBW_ThNo,
        SW_SEL   => WBW_SEL,
        SW_DAT   => WBW_DAT,
        -- AxiS Read Request
        SR_Valid => WBRA_Valid,
        SR_Ready => WBRA_Ready,
        SR_ADR   => WBRA_ADR,
        SR_ThNo  => WBRA_ThNo,
        -- AxiS Read Response
        MR_Valid => WBRR_Valid,
        MR_Ready => WBRR_Ready,
        MR_DAT   => WBRR_DAT,
        -- Wishbone Bus
        WB_STB   => WB_STB,
        WB_WE    => WB_WE,
        WB_SEL   => WB_SEL,
        WB_ADR   => WB_ADR,
        WB_ThNo  => WB_ThNo,
        WB_MOSI  => WB_MOSI,
        WB_MISO  => WB_MISO,
        WB_ACK   => WB_ACK
      );
      
    ------------------------------------------------------------
    -- Wishbone Bus Decoding
    ------------------------------------------------------------
    WB_DBus_Decoder: block
      --signal WB_FULL_ADR : unsigned(ADR_WIDTH-1 downto 0);
      function CheckMemWindow(ADR: std_logic_vector; DEV_BASE: unsigned; DEV_ldSize: integer) return boolean is
        variable ADRinRange: boolean := true;
        constant ADR_Bits : natural := ADR'Length+2;
      begin
        if    unsigned(ADR&"00") <   DEV_BASE(ADR_Bits-1 downto 0)                   then ADRinRange := false;
        elsif unsigned(ADR&"00") > ((DEV_BASE(ADR_Bits-1 downto 0)-1)+2**DEV_ldSize) then ADRinRange := false;
        end if;
        return ADRinRange;
      end;
    begin
      -- Address-Decoder
      GPIO_STB     <= WB_STB when CheckMemWindow(WB_ADR, GPIO_BASE,     GPIO_ldSize)     else '0';
      Timer_STB    <= WB_STB when CheckMemWindow(WB_ADR, Timer_BASE,    Timer_ldSize)    else '0';
      UART_STB     <= WB_STB when CheckMemWindow(WB_ADR, UART_BASE,     UART_ldSize)     else '0';
      -- WB-Read-Mux
      WB_MISO     <= GPIO_MISO     when GPIO_STB     = '1' else
                     TIMER_MISO    when Timer_STB    = '1' else
                     UART_MISO     when UART_STB     = '1' else
                     (others=>'-');
      -- WB-ACK-Mux
      WB_ACK      <= GPIO_ACK     when GPIO_STB     = '1' else
                     Timer_ACK    when Timer_STB    = '1' else
                     UART_ACK     when UART_STB     = '1' else
                     '0';
    end block;

    ------------------------------------------------------------
    -- GPIO
    ------------------------------------------------------------
    GPIO_Inst: entity work.GPIO
    generic map ( N => PINS'length )
      port map (
      CLK_I     => CLK,
      RST_I     => RESET,
      STB_I     => GPIO_STB,
      WE_I      => WB_WE,
      SEL_I     => WB_SEL,
      ADR_I     => WB_ADR(GPIO_ldSize - 1 downto 2),
      DAT_I     => WB_MOSI,
      ACK_O     => GPIO_ACK,
      DAT_O     => GPIO_MISO,
      Pins      => PINS,
      Interrupt => Interrupts(0)
    );

    ------------------------------------------------------------
    -- Timer
    ------------------------------------------------------------
    Timer_Inst: entity work.Timer
    generic map ( N => 32 )
    port map(
      CLK_I     => CLK,
      RST_I     => RESET,
      STB_I     => Timer_STB,
      WE_I      => WB_WE,
      SEL_I     => WB_SEL,
      ADR_I     => WB_ADR(TIMER_ldSize - 1 downto 2),
      DAT_I     => WB_MOSI,
      ACK_O     => Timer_ACK,
      DAT_O     => Timer_MISO,
      Interrupt => Interrupts(1),
      PWM       => PWM
    );
    
    ------------------------------------------------------------
    -- UART
    ------------------------------------------------------------
    UART_Inst: entity work.UART
      port map (
        -- 
        CLK_I      => CLK,
        RST_I      => RESET,
        -- Wishbone Bus
        STB_I      => UART_STB,
        WE_I       => WB_WE,
        ADR_I      => WB_ADR(UART_ldSize - 1 downto 2),
        DAT_I      => WB_MOSI,
        DAT_O      => UART_MISO,
        ACK_O      => UART_ACK,
        -- Interupt
        Interrupt  => Interrupts(2),
        -- Serial IOs
        RxD        => RxD,
        TxD        => TxD
      );
    
  end block;
      
end arch;
