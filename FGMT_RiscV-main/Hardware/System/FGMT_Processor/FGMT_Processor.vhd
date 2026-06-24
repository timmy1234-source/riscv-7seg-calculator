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
entity FGMT_Processor is
  generic (
    Frequency           : integer := 50_000_000;
    ADR_WIDTH           : integer := 16;
    THREAD_NO_WIDTH     : integer :=  3;
    ERR_ID_WIDTH        : integer :=  2;
    TH_ACTIVITY_TIMEOUT : integer := 15;
    INTERRUPT_COUNT     : integer :=  8;
	  ------------------------------------------------------------
    -- Start address and number of starting thread
	  ------------------------------------------------------------
    Startaddress        : integer := 0;
    StartThread         : integer := 0
  );
  port (
    CLK        : in  std_logic;
    RESET      : in  std_logic;
    -- Serial Debugger Port
    GDB_RxD    : in  std_logic;
    GDB_TxD    : out std_logic;
    -- Interrupts
    Interrupts : in  std_logic_vector(INTERRUPT_COUNT-1 downto 0);
    -- Info outputs
    ActThreads : out std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    ThActivity : out std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
    ErrVect    : out std_logic_vector(31 downto 0);
    AxsVect    : out std_logic_vector(31 downto 0);
    -- IBUS --
    -- IBUS: Stream to Instruction Memory: Address Stream
    MI_Valid   : out std_logic;
    MI_Ready   : in  std_logic;
    MI_ADR     : out std_logic_vector(ADR_WIDTH-1 downto 1);
    MI_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- IBUS Stream from Instruction Memory: Data Stream
    SI_Valid   : in  std_logic;
    SI_Ready   : out std_logic;
    SI_Inst    : in  std_logic_vector(31 downto 0);
    -- DBUS --
    -- DBUS: Data Memory Write stream
    MW_Valid   : out std_logic;
    MW_Ready   : in  std_logic;
    MW_ADR     : out std_logic_vector(ADR_WIDTH-1 downto 2);
    MW_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    MW_DAT     : out std_logic_vector(31 downto 0);
    MW_SEL     : out std_logic_vector(3 downto 0);
    -- DBUS: Data Memory Read Address stream
    MR_Valid   : out std_logic;
    MR_Ready   : in  std_logic;
    MR_ADR     : out std_logic_vector(ADR_WIDTH-1 downto 2);
    MR_ThNo    : out std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    -- DBUS: Data Memory Read Response stream
    SR_Valid   : in  std_logic;
    SR_Ready   : out std_logic;
    SR_DAT     : in  std_logic_vector(31 downto 0)
  );
	------------------------------------------------------------
	--Address Map
	------------------------------------------------------------
  constant INT_WB_BASE     : unsigned(31 downto 0) := x"FFFFFF00"; -- Start of internal wishbone bus peripherals
	constant INT_WB_ldSize   : natural := 8;                         -- Internal peripherals occupy 2**8 bytes of address space
  -- Common used Peripherals
	constant ThSv_BASE       : unsigned(31 downto 0) := x"FFFFFFF8";
	constant ThSv_ldSize     : natural               := 4;
	constant Launcher_BASE   : unsigned(31 downto 0) := x"FFFFFFE0";
	constant Launcher_ldSize : natural               := 4;
	constant EXT_IRC_BASE    : unsigned(31 downto 0) := x"FFFFFFD0";
	constant EXT_IRC_ldSize  : natural               := 4;
  -- Debug Interface Peripherals
	constant DBG_IRC_BASE    : unsigned(31 downto 0) := x"FFFFFFA0";
	constant DBG_IRC_ldSize  : natural               := 4;
	constant DBG_UART_BASE   : unsigned(31 downto 0) := x"FFFFFF90";
	constant DBG_UART_ldSize : natural               := 4;
	constant DBG_ERR_BASE    : unsigned(31 downto 0) := x"FFFFFF80";
	constant DBG_ERR_ldSize  : natural               := 4;
	constant DBG_IF_BASE     : unsigned(31 downto 0) := x"FFFFFF40";
	constant DBG_IF_ldSize   : natural               := 6;
	constant HW_BKP_BASE     : unsigned(31 downto 0) := x"FFFFFF00";
	constant HW_BKP_ldSize   : natural               := 6;
end FGMT_Processor;

architecture arch of FGMT_Processor is
  signal RESETN     : std_logic;
  -- Processing Pipeline Input Stream from Thread Fifo
  signal PI_Valid   : std_logic;
  signal PI_Ready   : std_logic;
  signal PI_PC      : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal PI_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Processing Pipeline to DS_SMUX3
  signal NX1_Valid_rd : std_logic;
  signal NX1_Ready_rd : std_logic;
  signal NX1_Valid  : std_logic;
  signal NX1_Ready  : std_logic;
  signal NX1_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal NX1_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from DS_SMUX3 to Thread Filter
  signal NX2_Valid  : std_logic;
  signal NX2_Ready  : std_logic;
  signal NX2_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal NX2_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Thread Filter to HW-Breakpoits
  signal NX3_Valid  : std_logic;
  signal NX3_Ready  : std_logic;
  signal NX3_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal NX3_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from HW-Breakpoits to DS_SMUX2
  signal NX4_Valid  : std_logic;
  signal NX4_Ready  : std_logic;
  signal NX4_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal NX4_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from DS_SMUX2 to Activity Supervisor
  signal NX5_Valid  : std_logic;
  signal NX5_Ready  : std_logic;
  signal NX5_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal NX5_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Activity Supervisor to Thread Fifo
  signal NX6_Valid  : std_logic;
  signal NX6_Ready  : std_logic;
  signal NX6_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal NX6_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Processing Pipeline WFI output to DS_DMUX
  signal WFI_Valid  : std_logic;
  signal WFI_Ready  : std_logic;
  signal WFI_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal WFI_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from DS_DMUX to Debug Interrupt Controller
  signal WFI0_Valid : std_logic;
  signal WFI0_Ready : std_logic;
  signal WFI0_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal WFI0_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Debug Interrupt Controller to DS_SMUX3
  signal WFD0_Valid : std_logic;
  signal WFD0_Ready : std_logic;
  signal WFD0_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal WFD0_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from DS_DMUX to Interrupt Controller for external IRs
  signal WFIx_Valid : std_logic;
  signal WFIx_Ready : std_logic;
  signal WFIx_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal WFIx_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Interrupt Controller for external IRs to DS_SMUX3
  signal WFDx_Valid : std_logic;
  signal WFDx_Ready : std_logic;
  signal WFDx_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal WFDx_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from Processing Pipeline Error Thread Fifo
  signal ERRF_Valid : std_logic;
  signal ERRF_Ready : std_logic;
  signal ERRF_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal ERRF_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal ERRF_ErrID : std_logic_vector(ERR_ID_WIDTH-1 downto 0);
  -- Stream from Error Thread Fifo to Error Handling
  signal ERR_Valid  : std_logic;
  signal ERR_Ready  : std_logic;
  signal ERR_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal ERR_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal ERR_ErrID  : std_logic_vector(ERR_ID_WIDTH-1 downto 0);
  -- Stream from Launcher to DS_SMUX2
  signal LNCH_Valid : std_logic;
  signal LNCH_Ready : std_logic;
  signal LNCH_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal LNCH_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from ProcessingPipeline ebreak port to ThreadFifo
  signal EBKF_Valid : std_logic;
  signal EBKF_Ready : std_logic;
  signal EBKF_PC    : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal EBKF_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from ThreadFifo to DebugInterface
  signal EBK_Valid  : std_logic;
  signal EBK_Ready  : std_logic;
  signal EBK_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal EBK_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from HW-Breakpoints to HBK ThreadFifo
  signal HBKF_Valid  : std_logic;
  signal HBKF_Ready  : std_logic;
  signal HBKF_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal HBKF_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from HBK ThreadFifo to DebugInterface
  signal HBK_Valid  : std_logic;
  signal HBK_Ready  : std_logic;
  signal HBK_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal HBK_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Stream from ThreadFilter to DebugInterface
  signal DBG_Valid  : std_logic;
  signal DBG_Ready  : std_logic;
  signal DBG_PC     : std_logic_vector(ADR_WIDTH-1 downto 0);
  signal DBG_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Data Memory Write stream from ProcessingPipeline to Interconnect
  signal WP2I_Valid  : std_logic;
  signal WP2I_Ready  : std_logic;
  signal WP2I_ADR    : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal WP2I_ThNo   : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal WP2I_DAT    : std_logic_vector(31 downto 0);
  signal WP2I_SEL    : std_logic_vector(3 downto 0);
  -- Data Memory Read Address stream from ProcessingPipeline to Interconnect
  signal RP2I_Valid : std_logic;
  signal RP2I_Ready : std_logic;
  signal RP2I_ADR   : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal RP2I_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Data Memory Read Response stream from Interconnect to ProcessingPipeline
  signal RI2P_Valid : std_logic;
  signal RI2P_Ready : std_logic;
  signal RI2P_DAT   : std_logic_vector(31 downto 0);
  -- Data Memory Write stream from Interconnect to WB_Bridge
  signal WI2W_Valid : std_logic;
  signal WI2W_Ready : std_logic;
  signal WI2W_ADR   : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal WI2W_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal WI2W_DAT   : std_logic_vector(31 downto 0);
  signal WI2W_SEL   : std_logic_vector(3 downto 0);
  -- Data Memory Read Address stream from Interconnect to WB_Bridge
  signal RI2W_Valid : std_logic;
  signal RI2W_Ready : std_logic;
  signal RI2W_ADR   : std_logic_vector(ADR_WIDTH-1 downto 2);
  signal RI2W_ThNo  : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  -- Data Memory Read Response stream from WB_Bridge to Interconnect
  signal RW2I_Valid : std_logic;
  signal RW2I_Ready : std_logic;
  signal RW2I_DAT   : std_logic_vector(31 downto 0);
  -- Injection signals
  signal IJ_Active  : std_logic;
  signal IJ_ThNo    : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
  signal IJ_Inst    : std_logic_vector(31 downto 0);
  signal IJ_RegV    : std_logic_vector(31 downto 0);
  signal TF_ThBits  : std_logic_vector(2**THREAD_NO_WIDTH-1 downto 0);
begin

  RESETN <= not RESET;

  PP: entity work.Processing_Pipeline
    generic map (
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK          => CLK,
      RESET        => RESET,
      -- Input
      S_Valid      => PI_Valid,
      S_Ready      => PI_Ready,
      S_PC         => PI_PC,
      S_ThNo       => PI_ThNo,
      -- IBUS: Stream to Instruction Memory: Address Stream
      MI_Valid     => MI_Valid,
      MI_Ready     => MI_Ready,
      MI_ADR       => MI_ADR,
      MI_ThNo      => MI_ThNo,
      -- IBUS: Stream from Instruction Memory: Data Stream
      SI_Valid     => SI_Valid,
      SI_Ready     => SI_Ready,
      SI_Inst      => SI_Inst,
      -- DBUS: Data Memory Write stream
      MW_Valid     => WP2I_Valid,
      MW_Ready     => WP2I_Ready,
      MW_ADR       => WP2I_ADR,
      MW_ThNo      => WP2I_ThNo,
      MW_DAT       => WP2I_DAT,
      MW_SEL       => WP2I_SEL,
      -- DBUS: Data Memory Read Address stream
      MR_Valid     => RP2I_Valid,
      MR_Ready     => RP2I_Ready,
      MR_ADR       => RP2I_ADR,
      MR_ThNo      => RP2I_ThNo,
      -- DBUS: Data Memory Read Response stream
      SR_Valid     => RI2P_Valid,
      SR_Ready     => RI2P_Ready,
      SR_DAT       => RI2P_DAT,
      -- Output
      M_Valid      => NX1_Valid_rd,
      M_Ready      => NX1_Ready_rd,
      M_PC         => NX1_PC,
      M_ThNo       => NX1_ThNo,
      -- Output to Interrupt Controller (IRC)
      Wfi_Valid    => WFI_Valid,
      Wfi_Ready    => WFI_Ready,
      Wfi_PC       => WFI_PC,
      Wfi_ThNo     => WFI_ThNo,
      -- Output for ebreak commands
      EBK_Valid    => EBKF_Valid,
      EBK_Ready    => EBKF_Ready,
      EBK_PC       => EBKF_PC,
      EBK_ThNo     => EBKF_ThNo,
      -- Error Output
      Mx_Valid     => ERRF_Valid,
      Mx_Ready     => ERRF_Ready,
      Mx_PC        => ERRF_PC,
      Mx_ThNo      => ERRF_ThNo,
      Mx_ErrID     => ERRF_ErrID,
      -- Injection signals
      IJ_Active    => IJ_Active,
      IJ_ThNo      => IJ_ThNo,
      IJ_Inst      => IJ_Inst,
      IJ_RegV      => IJ_RegV,
      --
      AxsVect      => AxsVect
    );

--  RD_NX1: entity work.DS_RandomDelay_VR
--    generic map (
--      RANDOM_SEED => 16#12367#,  -- range 0 to 16#fffff#
--      ENABLE_DLY  => true
--    )
--    port map (
--      -- common signals
--      ACLK       => CLK,
--      ARESETN    => RESETN,
--      -- input interface
--      s_valid    => NX1_Valid_rd,
--      s_ready    => NX1_Ready_rd,
--      -- output interface
--      m_valid    => NX1_Valid,
--      m_ready    => NX1_Ready
--    );
  NX1_Valid <= NX1_Valid_rd;
  NX1_Ready_rd <= NX1_Ready;

  WFI_DMUX: entity work.DS_DMUX
    generic map (
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      -- Input
      S_Valid   => WFI_Valid,
      S_Ready   => WFI_Ready,
      S_PC      => WFI_PC,
      S_ThNo    => WFI_ThNo,
      -- Output (0) 
      M0_Valid  => WFI0_Valid,
      M0_Ready  => WFI0_Ready,
      M0_PC     => WFI0_PC,
      M0_ThNo   => WFI0_ThNo,
      -- Output (1) 
      M1_Valid  => WFIx_Valid,
      M1_Ready  => WFIx_Ready,
      M1_PC     => WFIx_PC,
      M1_ThNo   => WFIx_ThNo
    );

  ERR_FF: entity work.ErrorFifo
    generic map (
      M               => THREAD_NO_WIDTH,
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH,
      ERR_ID_WIDTH    => ERR_ID_WIDTH
    )
    port map (
      CLK     => CLK,
      RESET   => RESET,
      -- Write
      S_Valid => ERRF_Valid,
      S_Ready => ERRF_Ready,
      S_PC    => ERRF_PC,
      S_ThNo  => ERRF_ThNo,
      S_ErrID => ERRF_ErrID,
      -- Read
      M_Valid => ERR_Valid,
      M_Ready => ERR_Ready,
      M_PC    => ERR_PC,
      M_ThNo  => ERR_ThNo,
      M_ErrID => ERR_ErrID
    );

  SMUX3: entity work.DS_SMUX3
    generic map (
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      -- Input (0) 
      S0_Valid => WFD0_Valid,
      S0_Ready => WFD0_Ready,
      S0_PC    => WFD0_PC,
      S0_ThNo  => WFD0_ThNo,
      -- Input (1) 
      S1_Valid => WFDx_Valid,
      S1_Ready => WFDx_Ready,
      S1_PC    => WFDx_PC,
      S1_ThNo  => WFDx_ThNo,
      -- Input (2) lowest priority
      S2_Valid => NX1_Valid,
      S2_Ready => NX1_Ready,
      S2_PC    => NX1_PC,
      S2_ThNo  => NX1_ThNo,
      -- Output
      M_Valid  => NX2_Valid,
      M_Ready  => NX2_Ready,
      M_PC     => NX2_PC,
      M_ThNo   => NX2_ThNo
    );
  
  THFI: entity work.ThreadFilter
    generic map (
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK       => CLK,
      RESET     => RESET,
      -- Controls
      TF_ThBits => TF_ThBits,
      -- Input
      S_Valid   => NX2_Valid,
      S_Ready   => NX2_Ready,
      S_PC      => NX2_PC,
      S_ThNo    => NX2_ThNo,
      -- Output
      DBG_Valid => DBG_Valid,
      DBG_Ready => DBG_Ready,
      DBG_PC    => DBG_PC,
      DBG_ThNo  => DBG_ThNo,
      -- Output
      M_Valid   => NX3_Valid,
      M_Ready   => NX3_Ready,
      M_PC      => NX3_PC,
      M_ThNo    => NX3_ThNo
    );

  SMUX2: entity work.DS_SMUX2
    generic map (
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      -- Input (0) highest priority
      S0_Valid => LNCH_Valid,
      S0_Ready => LNCH_Ready,
      S0_PC    => LNCH_PC,
      S0_ThNo  => LNCH_ThNo,
      -- Input (1) lowest priority
      S1_Valid => NX4_Valid,
      S1_Ready => NX4_Ready,
      S1_PC    => NX4_PC,
      S1_ThNo  => NX4_ThNo,
      -- Output
      M_Valid  => NX5_Valid,
      M_Ready  => NX5_Ready,
      M_PC     => NX5_PC,
      M_ThNo   => NX5_ThNo
    );

  PPTHFF: entity work.ThreadFifo
    generic map (
      M               => THREAD_NO_WIDTH,
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK     => CLK,
      RESET   => RESET,
      -- Write
      S_Valid => NX6_Valid,
      S_Ready => NX6_Ready,
      S_PC    => NX6_PC,
      S_ThNo  => NX6_ThNo,
      -- Read
      M_Valid => PI_Valid,
      M_Ready => PI_Ready,
      M_PC    => PI_PC,
      M_ThNo  => PI_ThNo
    );

  EBKTHFF: entity work.ThreadFifo
    generic map (
      M               => THREAD_NO_WIDTH,
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK     => CLK,
      RESET   => RESET,
      -- Write
      S_Valid => EBKF_Valid,
      S_Ready => EBKF_Ready,
      S_PC    => EBKF_PC,
      S_ThNo  => EBKF_ThNo,
      -- Read
      M_Valid => EBK_Valid,
      M_Ready => EBK_Ready,
      M_PC    => EBK_PC,
      M_ThNo  => EBK_ThNo
    );
    
  HBKTHFF: entity work.ThreadFifo
    generic map (
      M               => THREAD_NO_WIDTH,
      ADR_WIDTH       => ADR_WIDTH,
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK     => CLK,
      RESET   => RESET,
      -- Write
      S_Valid => HBKF_Valid,
      S_Ready => HBKF_Ready,
      S_PC    => HBKF_PC,
      S_ThNo  => HBKF_ThNo,
      -- Read
      M_Valid => HBK_Valid,
      M_Ready => HBK_Ready,
      M_PC    => HBK_PC,
      M_ThNo  => HBK_ThNo
    );
    
  INTERCONN: entity work.Interconnect
    generic map (
      ADDR_WIDTH      => ADR_WIDTH,
      ADR0_BASE       => INT_WB_BASE,      -- Processor internal peripherals, base
      ADR0_SIZE       => 2**INT_WB_ldSize, -- Processor internal peripherals, size
      THREAD_NO_WIDTH => THREAD_NO_WIDTH
    )
    port map (
      CLK       => CLK,
      RESET     => RESET,
      -- Read Request Input, from processing pipeline
      SR_Valid  => RP2I_Valid,
      SR_Ready  => RP2I_Ready,
      SR_ADR    => RP2I_ADR,
      SR_ThNo   => RP2I_ThNo,
      -- Read Response Output, to processing pipeline
      MR_Valid  => RI2P_Valid,
      MR_Ready  => RI2P_Ready,
      MR_DAT    => RI2P_DAT,
      -- Read Request Output 0, to wishbone bridge
      MR0_Valid => RI2W_Valid,
      MR0_Ready => RI2W_Ready,
      MR0_ADR   => RI2W_ADR,
      MR0_ThNo  => RI2W_ThNo,
      -- Read Response Input 0, from wishbone bridge
      SR0_Valid => RW2I_Valid,
      SR0_Ready => RW2I_Ready,
      SR0_DAT   => RW2I_DAT,
      -- Read Request Output 1
      MR1_Valid => MR_Valid,
      MR1_Ready => MR_Ready,
      MR1_ADR   => MR_ADR,  
      MR1_ThNo  => MR_ThNo,
      -- Read Response Input 1
      SR1_Valid => SR_Valid,
      SR1_Ready => SR_Ready,
      SR1_DAT   => SR_DAT,  
      -- Write Request Input, from processing pipeline
      SW_Valid  => WP2I_Valid,
      SW_Ready  => WP2I_Ready,
      SW_DAT    => WP2I_DAT,
      SW_SEL    => WP2I_SEL,
      SW_ADR    => WP2I_ADR,
      SW_ThNo   => WP2I_ThNo,
      -- Write Request Output 0, to wishbone bridge
      MW0_Valid => WI2W_Valid,
      MW0_Ready => WI2W_Ready,
      MW0_DAT   => WI2W_DAT,
      MW0_SEL   => WI2W_SEL,
      MW0_ADR   => WI2W_ADR,
      MW0_ThNo  => WI2W_ThNo,
      -- Write Request Output 1
      MW1_Valid => MW_Valid,
      MW1_Ready => MW_Ready,
      MW1_DAT   => MW_DAT,
      MW1_SEL   => MW_SEL,
      MW1_ADR   => MW_ADR,
      MW1_ThNo  => MW_ThNo
    );

  WB_BLOCK: block
    -- Wishbone Bus
    signal WB_STB          : std_logic;
    signal WB_WE           : std_logic;
    signal WB_SEL          : std_logic_vector( 3 downto 0);
    signal WB_ADR          : std_logic_vector(ADR_WIDTH-1 downto 2);
    signal WB_ThNo         : std_logic_vector(THREAD_NO_WIDTH-1 downto 0);
    signal WB_MOSI         : std_logic_vector(31 downto 0);
    signal WB_MISO         : std_logic_vector(31 downto 0);
    signal WB_ACK          : std_logic;
    -- ThreadInfo
    signal ThSv_STB        : std_logic;
    signal ThSv_ACK        : std_logic;
    signal ThSv_MISO       : std_logic_vector(31 downto 0);
    -- Launcher
    signal Launcher_STB    : std_logic;
    signal Launcher_ACK    : std_logic;
    signal Launcher_MISO   : std_logic_vector(31 downto 0);
    -- Interrupt Controller for external interrupts (EXT_IRC)
    signal EXT_IRC_STB     : std_logic;
    signal EXT_IRC_ACK     : std_logic;
    signal EXT_IRC_MISO    : std_logic_vector(31 downto 0);
    -- Interrupt Controller for debugging interrupts (DBG_IRC)
    signal DBG_IRC_STB     : std_logic;
    signal DBG_IRC_ACK     : std_logic;
    signal DBG_IRC_MISO    : std_logic_vector(31 downto 0);
    -- UART for debugging connection to GDB
    signal DBG_UART_STB    : std_logic;
    signal DBG_UART_ACK    : std_logic;
    signal DBG_UART_MISO   : std_logic_vector(31 downto 0);
    signal DBG_UART_IR     : std_logic;
    -- Debug error handling
    signal DBG_Err_STB     : std_logic;
    signal DBG_Err_ACK     : std_logic;
    signal DBG_Err_MISO    : std_logic_vector(31 downto 0);
    signal DBG_Err_IR      : std_logic;
    -- Debug interface
    signal DBG_IF_STB      : std_logic;
    signal DBG_IF_ACK      : std_logic;
    signal DBG_IF_MISO     : std_logic_vector(31 downto 0);
    signal DBG_IF_IR       : std_logic;
    -- Hardware Breakpoints
    signal HW_BKP_STB      : std_logic;
    signal HW_BKP_ACK      : std_logic;
    signal HW_BKP_MISO     : std_logic_vector(31 downto 0);
    signal HW_BKP_IR       : std_logic;
    --
    signal Thread0_STB     : std_logic;
    signal DBG_Interrupts  : std_logic_vector(2 downto 0);
    signal KillThreads         : std_logic;
  begin

    PROCWBB: entity work.WB_Bridge
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
        SW_Valid => WI2W_Valid,
        SW_Ready => WI2W_Ready,
        SW_ADR   => WI2W_ADR,
        SW_ThNo  => WI2W_ThNo,
        SW_SEL   => WI2W_SEL,
        SW_DAT   => WI2W_DAT,
        -- AxiS Read Request
        SR_Valid => RI2W_Valid,
        SR_Ready => RI2W_Ready,
        SR_ADR   => RI2W_ADR,
        SR_ThNo  => RI2W_ThNo,
        -- AxiS Read Response
        MR_Valid => RW2I_Valid,
        MR_Ready => RW2I_Ready,
        MR_DAT   => RW2I_DAT,
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
      -- Select some Peripherals only for thread 0
      Thread0_STB <= WB_STB when unsigned(WB_ThNo)=0 else '0';
      -- Address-Decoder
      ThSv_STB     <= WB_STB      when CheckMemWindow(WB_ADR, ThSv_BASE,     ThSv_ldSize)   else '0';
      Launcher_STB <= WB_STB      when CheckMemWindow(WB_ADR, Launcher_BASE, Launcher_ldSize) else '0';
      EXT_IRC_STB  <= WB_STB      when CheckMemWindow(WB_ADR, EXT_IRC_BASE,  EXT_IRC_ldSize)  else '0';
      DBG_IRC_STB  <= Thread0_STB when CheckMemWindow(WB_ADR, DBG_IRC_BASE,  DBG_IRC_ldSize)  else '0';
      DBG_UART_STB <= Thread0_STB when CheckMemWindow(WB_ADR, DBG_UART_BASE, DBG_UART_ldSize) else '0';
      DBG_ERR_STB  <= Thread0_STB when CheckMemWindow(WB_ADR, DBG_ERR_BASE,  DBG_ERR_ldSize)  else '0';
      DBG_IF_STB   <= WB_STB      when CheckMemWindow(WB_ADR, DBG_IF_BASE,   DBG_IF_ldSize)   else '0';
      HW_BKP_STB   <= Thread0_STB when CheckMemWindow(WB_ADR, HW_BKP_BASE,   HW_BKP_ldSize)   else '0';
      -- WB-Read-Mux
      WB_MISO <= ThSv_MISO     when ThSv_STB     = '1' else
                 Launcher_MISO when Launcher_STB = '1' else
                 EXT_IRC_MISO  when EXT_IRC_STB  = '1' else
                 DBG_IRC_MISO  when DBG_IRC_STB  = '1' else
                 DBG_UART_MISO when DBG_UART_STB = '1' else
                 DBG_ERR_MISO  when DBG_ERR_STB  = '1' else
                 DBG_IF_MISO   when DBG_IF_STB   = '1' else
                 HW_BKP_MISO   when HW_BKP_STB   = '1' else
                 (others=>'-');
      -- WB-ACK-Mux
      WB_ACK  <= ThSv_ACK     when ThSv_STB     = '1' else
                 Launcher_ACK when Launcher_STB = '1' else
                 EXT_IRC_ACK  when EXT_IRC_STB  = '1' else
                 DBG_IRC_ACK  when DBG_IRC_STB  = '1' else
                 DBG_UART_ACK when DBG_UART_STB = '1' else
                 DBG_ERR_ACK  when DBG_ERR_STB  = '1' else
                 DBG_IF_ACK   when DBG_IF_STB   = '1' else
                 HW_BKP_ACK   when HW_BKP_STB   = '1' else
                 '0';
    end block;

    ------------------------------------------------------------
    -- ThreadSupervisor
    ------------------------------------------------------------
    ThSv: entity work.ThreadSupervisor
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH,
        TIME_OUT        => TH_ACTIVITY_TIMEOUT
      )
      port map (
        CLK            => CLK,
        RESET          => RESET,
        KillThreads    => KillThreads,
        -- Wishbone bus
        WB_STB         => ThSv_STB,
        WB_ADR         => WB_ADR(ThSv_ldSize-1 downto 2),
        WB_THNO        => WB_ThNo,
        WB_SEL         => WB_SEL,
        WB_WE          => WB_WE,
        WB_MOSI        => WB_MOSI,
        WB_MISO        => ThSv_MISO,
        WB_ACK         => ThSv_ACK,
        -- Stream Input
        S_Valid        => NX5_Valid,
        S_Ready        => NX5_Ready,
        S_PC           => NX5_PC,
        S_ThNo         => NX5_ThNo,
        -- Stream Output
        M_Valid        => NX6_Valid,
        M_Ready        => NX6_Ready,
        M_PC           => NX6_PC,
        M_ThNo         => NX6_ThNo,
        -- Thread Activity Output
        ThreadActivity => ThActivity,
        ActiveThreads  => ActThreads
      );

    ------------------------------------------------------------
    -- Launcher
    ------------------------------------------------------------
    Launcher_Inst: entity work.Launcher
      generic map (
        Start_Valid  => '1',
        StartAddress => std_logic_vector(to_unsigned(StartAddress,ADR_WIDTH)),
        StartThread  => std_logic_vector(to_unsigned(StartThread,THREAD_NO_WIDTH))
      )
      port map (
        CLK          => CLK,
        RESET        => RESET,
        -- Wishbone bus
        WB_STB       => Launcher_STB,
        WB_ADR       => WB_ADR(Launcher_ldSize - 1 downto 2),
        WB_THNO      => WB_ThNo,
        WB_SEL       => WB_SEL,
        WB_WE        => WB_WE,
        WB_MOSI      => WB_MOSI,
        WB_MISO      => Launcher_MISO,
        WB_ACK       => Launcher_ACK,
        -- Stream output
        Lch_Valid    => LNCH_Valid,
        Lch_Ready    => LNCH_Ready,
        Lch_PC       => LNCH_PC,
        Lch_ThNo     => LNCH_ThNo
      );

    ------------------------------------------------------------
    -- Interrupt controller for external interrupts
    ------------------------------------------------------------
    EXT_IRC_Inst: entity work.IRC
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH,
        NUMBER_OF_IRS   => INTERRUPT_COUNT,  -- Values in range 32..1
        WITH_READYSYNC  => true
      )
      port map (
        CLK       => CLK,
        RESET     => RESET,
        KillThreads   => KillThreads,
        -- Wishbone bus
        WB_STB    => EXT_IRC_STB,
        WB_ADR    => WB_ADR(EXT_IRC_ldSize - 1 downto 2),
        WB_SEL    => WB_SEL,
        WB_WE     => WB_WE,
        WB_MOSI   => WB_MOSI,
        WB_MISO   => EXT_IRC_MISO,
        WB_ACK    => EXT_IRC_ACK,
        -- Interrupt inputs
        Interrupt => Interrupts,
        -- Stream input
        S_Valid   => WFIx_Valid,
        S_Ready   => WFIx_Ready,
        S_PC      => WFIx_PC,
        S_ThNo    => WFIx_ThNo,
        -- Stream output
        M_Valid   => WFDx_Valid,
        M_Ready   => WFDx_Ready,
        M_PC      => WFDx_PC,
        M_ThNo    => WFDx_ThNo
      );

    ------------------------------------------------------------
    -- Interrupt controller for debug interface interrupts
    ------------------------------------------------------------
    DBG_IRC_Inst: entity work.IRC
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH,
        NUMBER_OF_IRS   => DBG_Interrupts'Length,  -- Debug interface, UART, Error handling
        WITH_READYSYNC  => true
      )
      port map (
        CLK         => CLK,
        RESET       => RESET,
        KillThreads => '0',
        -- Wishbone bus
        WB_STB      => DBG_IRC_STB,
        WB_ADR      => WB_ADR(DBG_IRC_ldSize - 1 downto 2),
        WB_SEL      => WB_SEL,
        WB_WE       => WB_WE,
        WB_MOSI     => WB_MOSI,
        WB_MISO     => DBG_IRC_MISO,
        WB_ACK      => DBG_IRC_ACK,
        -- Interrupt inputs
        Interrupt   => DBG_Interrupts,
        -- Stream input
        S_Valid     => WFI0_Valid,
        S_Ready     => WFI0_Ready,
        S_PC        => WFI0_PC,
        S_ThNo      => WFI0_ThNo,
        -- Stream output
        M_Valid     => WFD0_Valid,
        M_Ready     => WFD0_Ready,
        M_PC        => WFD0_PC,
        M_ThNo      => WFD0_ThNo
      );

    ------------------------------------------------------------
    -- UART for debug communication to GDB
    ------------------------------------------------------------
    DBG_UART_Inst: entity work.UART
      port map (
        -- 
        CLK_I      => CLK,
        RST_I      => RESET,
        -- Wishbone Bus
        STB_I      => DBG_UART_STB,
        WE_I       => WB_WE,
        ADR_I      => WB_ADR(DBG_UART_ldSize - 1 downto 2),
        DAT_I      => WB_MOSI,
        DAT_O      => DBG_UART_MISO,
        ACK_O      => DBG_UART_ACK,
        -- Interupt
        Interrupt  => DBG_Interrupts(0),
        -- Port Pins
        RxD        => GDB_RxD,
        TxD        => GDB_TxD
      );

    ------------------------------------------------------------
    -- ErrHandling: component to receive error tokens 
    ------------------------------------------------------------
    DBG_ERR_inst: entity work.ErrHandling
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH,
        ERR_ID_WIDTH    => ERR_ID_WIDTH
      )
      port map (
        CLK           => CLK,
        RESET         => RESET,
        -- Wishbone bus
        WB_STB        => DBG_ERR_STB,
        WB_ADR        => WB_ADR(DBG_ERR_ldSize - 1 downto 2),
        WB_SEL        => WB_SEL,
        WB_WE         => WB_WE,
        WB_MOSI       => WB_MOSI,
        WB_MISO       => DBG_ERR_MISO,
        WB_ACK        => DBG_ERR_ACK,
        -- Error Token Input
        Err_Valid     => ERR_Valid,
        Err_Ready     => ERR_Ready,
        Err_PC        => ERR_PC,
        Err_ThNo      => ERR_ThNo,
        Err_ErrID     => ERR_ErrID,
        -- Interrupt output
        Err_Interrupt => DBG_Interrupts(1)
      );
    process(ERR_Valid, ERR_PC, ERR_ThNo, ERR_ErrID)
    begin
      ErrVect <= (others => '0');
      ErrVect(THREAD_NO_WIDTH+ERR_ID_WIDTH+15 downto 16) <= ERR_ThNo & ERR_ErrID;
      ErrVect(ADR_WIDTH-1 downto 0) <= ERR_PC;
      ErrVect(31) <= ERR_Valid; 
    end process;
    ------------------------------------------------------------
    -- DebugInterface: central debugging component 
    ------------------------------------------------------------
    DBG_IF_inst: entity work.DebugInterface
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH
      )
      port map (
        CLK           => CLK,
        RESET         => RESET,
        -- Wishbone bus
        WB_STB        => DBG_IF_STB,
        WB_ADR        => WB_ADR(DBG_IF_ldSize - 1 downto 2),
        WB_SEL        => WB_SEL,
        WB_WE         => WB_WE,
        WB_MOSI       => WB_MOSI,
        WB_MISO       => DBG_IF_MISO,
        WB_ACK        => DBG_IF_ACK,
        -- Debug Streaming Input
        DBG_Valid     => DBG_Valid,
        DBG_Ready     => DBG_Ready,
        DBG_PC        => DBG_PC,
        DBG_ThNo      => DBG_ThNo,
        -- Ebreak Streaming Input
        EBK_Valid     => EBK_Valid,
        EBK_Ready     => EBK_Ready,
        EBK_PC        => EBK_PC,
        EBK_ThNo      => EBK_ThNo,
        -- Hardware Breakpoint Streaming Input
        HBK_Valid     => HBK_Valid,
        HBK_Ready     => HBK_Ready,
        HBK_PC        => HBK_PC,
        HBK_ThNo      => HBK_ThNo,
        -- Inputs and Outputs
        TF_ThBits     => TF_ThBits,
        IJ_Inst       => IJ_Inst,
        IJ_Active     => IJ_Active,
        IJ_ThNo       => IJ_ThNo,
        IJ_RegV       => IJ_RegV,
        KillThreads   => KillThreads,
        DBI_Interrupt => DBG_Interrupts(2)
      );
      
    HWBK_inst: entity work.HardwareBreakpoints
      generic map (
        ADR_WIDTH       => ADR_WIDTH,
        THREAD_NO_WIDTH => THREAD_NO_WIDTH,
        WITH_DATASYNC   => true
      )
      port map (
        CLK       => CLK,
        RESET     => RESET,
        -- Wishbone bus
        WB_STB    => HW_BKP_STB,
        WB_ADR    => WB_ADR(HW_BKP_ldSize - 1 downto 2),
        WB_SEL    => WB_SEL,
        WB_WE     => WB_WE,
        WB_MOSI   => WB_MOSI,
        WB_MISO   => HW_BKP_MISO,
        WB_ACK    => HW_BKP_ACK,
        -- Debug Streaming Input
        S_Valid   => NX3_Valid,
        S_Ready   => NX3_Ready,
        S_PC      => NX3_PC,
        S_ThNo    => NX3_ThNo,
        -- Ebreak Streaming Input
        HBK_Valid => HBKF_Valid,
        HBK_Ready => HBKF_Ready,
        HBK_PC    => HBKF_PC,
        HBK_ThNo  => HBKF_ThNo,
        -- Hardware Breakpoint Streaming Input
        M_Valid   => NX4_Valid,
        M_Ready   => NX4_Ready,
        M_PC      => NX4_PC,
        M_ThNo    => NX4_ThNo
      );

  end block;
 
end arch;
