-----------------------------------------------------------------------------------
-- Memory with half word aligned read access (needed for compressed instructions)
-- B. Lang
-----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Memory_Read_Simple_Write_16AR is
	generic (
		MEM_ldSIZE   : natural := 15;
		BASE_ADDR     : natural := 16#0000#;
		HEX_FILE_NAME : string  := "./Source/Memory/Software_Leer.hex"
	);
	port (
		CLK       : in  std_logic;
		RESET     : in  std_logic;
    -- Read Request from Instruction Port
    S0R_Valid : in  std_logic;
    S0R_Ready : out std_logic;
    S0R_ADR   : in  std_logic_vector(MEM_ldSIZE - 1 downto 1);
    -- Read Response to Instruction Port
    M0R_Valid : out std_logic;
    M0R_Ready : in  std_logic;
    M0R_DAT   : out std_logic_vector(31 downto 0);
    -- Read Request from Data Port
    S1R_Valid : in  std_logic;
    S1R_Ready : out std_logic;
    S1R_ADR   : in  std_logic_vector(MEM_ldSIZE - 1 downto 1);
    -- Read Response to Data Port
    M1R_Valid : out std_logic;
    M1R_Ready : in  std_logic;
    M1R_DAT   : out std_logic_vector(31 downto 0);
    -- Write Request from Data Port
    SW_Valid  : in  std_logic;
    SW_Ready  : out std_logic;
    SW_ADR    : in  std_logic_vector(MEM_ldSIZE - 1 downto 2);
    SW_SEL    : in  std_logic_vector(3 downto 0);
    SW_DAT    : in  std_logic_vector(31 downto 0)
	);
end entity;

library ieee;
use work.intel_hex_pack.all;
architecture arch of Memory_Read_Simple_Write_16AR is
  signal SR_Valid    : std_logic;
  signal SR_Ready    : std_logic;
  signal SR_Channel  : std_logic;
  signal SR_ADR      : std_logic_vector(MEM_ldSIZE - 1 downto 1);
  signal SR_Priority : std_logic;
  signal RS_Valid    : std_logic;
  signal RS_Ready    : std_logic;
  signal RS_Channel  : std_logic;
  signal RS_ADR      : std_logic_vector(MEM_ldSIZE - 1 downto 1);
  signal Xchange     : std_logic;
  signal X_upper     : std_logic_vector(15 downto 0);
  signal X_lower     : std_logic_vector(15 downto 0);
  signal MR_Valid    : std_logic;
  signal MR_Ready    : std_logic;
  signal MR_Channel  : std_logic;
  signal MR_DAT      : std_logic_vector(31 downto 0);
  signal upper_mem   : half_mem_type(0 to 2 ** (MEM_ldSIZE - 2) - 1) := extract_halflane(1,intel_hex_read(HEX_FILE_NAME, BASE_ADDR, 2 ** MEM_ldSIZE));
  signal lower_mem   : half_mem_type(0 to 2 ** (MEM_ldSIZE - 2) - 1) := extract_halflane(0,intel_hex_read(HEX_FILE_NAME, BASE_ADDR, 2 ** MEM_ldSIZE));
begin

--  DS_MUX_PRIO: process(CLK)
--  begin
--    if rising_edge(CLK) then
--      if RESET='1' then
--        SR_Priority <= '0';
--      elsif SR_Valid='1' and SR_Channel='1' and SR_Ready='1' then
--        SR_Priority <= '0';
--      elsif SR_Valid='1' and SR_Channel='0' and SR_Ready='1' then
--        SR_Priority <= '1';
--      end if;
--    end if;
--  end process;

--  DS_MUX: process(S0R_Valid, S0R_ADR, S1R_Valid, S1R_ADR, SR_Ready, SR_Priority)
--  begin
--    SR_Valid   <= '0';
--    SR_Channel <= '0';
--    SR_ADR     <= (SR_ADR'range => '-');
--    S0R_Ready  <= '0';
--    S1R_Ready  <= '0';
--    if (S0R_Valid='1') and (S1R_Valid='1') and (SR_Priority='1') then
--      SR_Valid   <= '1';
--      SR_Channel <= '1';
--      SR_ADR     <= S1R_ADR;
--      S1R_Ready  <= SR_Ready;
--    elsif S0R_Valid='1' then
--      SR_Valid   <= '1';
--      SR_Channel <= '0';
--      SR_ADR     <= S0R_ADR;
--      S0R_Ready  <= SR_Ready;
--    elsif S1R_Valid='1' then
--      SR_Valid   <= '1';
--      SR_Channel <= '1';
--      SR_ADR     <= S1R_ADR;
--      S1R_Ready  <= SR_Ready;
--    end if;
--  end process;

--  DS_MUX: process(S0R_Valid, S0R_ADR, S1R_Valid, S1R_ADR, SR_Ready)
--  begin
--    SR_Valid   <= '0';
--    SR_Channel <= '0';
--    SR_ADR     <= (SR_ADR'range => '-');
--    S0R_Ready  <= '0';
--    S1R_Ready  <= '0';
--    if S1R_Valid='1' then -- Data read (channel 1) has priority
--      SR_Valid   <= '1';
--      SR_Channel <= '1';
--      SR_ADR     <= S1R_ADR;
--      S1R_Ready  <= SR_Ready;
--    elsif S0R_Valid='1' then
--      SR_Valid   <= '1';
--      SR_Channel <= '0';
--      SR_ADR     <= S0R_ADR;
--      S0R_Ready  <= SR_Ready;
--    end if;
--  end process;

  DS_MUX: block
    type MuxSelT is (S1,S0,none);
    signal MuxSel : MuxSelT := none;
    type States is (MUX, Wait1, Wait0,Err);
    signal State: States;
    signal NextState: States;
		signal z: std_logic_vector(3 downto 0);
  begin
    SR_ADR     <= S0R_ADR when MuxSel=S0 else
                  S1R_ADR when MuxSel=S1 else
                  (SR_ADR'range => '-');
    SR_Channel <= '0' when MuxSel=S0 else
                  '1' when MuxSel=S1 else
                  '-';
    Mealy_Next: process(State, S0R_Valid, S1R_Valid, SR_Ready)
    begin
      if RESET='1' then
        NextState <= MUX;
        SR_Valid  <= '0';
        S0R_Ready <= '0';
        S1R_Ready <= '0';
        MuxSel    <= none;
      elsif RESET/='0' then
        NextState <= Err;
        SR_Valid  <= 'X';
        S0R_Ready <= 'X';
        S1R_Ready <= 'X';
        MuxSel    <= none;
      else
        NextState <= Err;
        SR_Valid  <= '0';
        S0R_Ready <= '0';
        S1R_Ready <= '0';
        MuxSel    <= none;
        case State is
          when MUX   =>
            if (S0R_Valid='0') and (S1R_Valid='0') then
              NextState <= MUX;
            elsif (S1R_Valid='1') and (SR_Ready='1') then
              NextState <= MUX;
              SR_Valid  <= '1';
              MuxSel    <= S1;
              S1R_Ready <= '1';
            elsif (S1R_Valid='1') and (SR_Ready='0') then
              NextState <= Wait1;
              SR_Valid  <= '1';
              MuxSel    <= S1;
            elsif (S1R_Valid='0') and (S0R_Valid='1') and (SR_Ready='1') then
              NextState <= MUX;
              SR_Valid  <= '1';
              MuxSel    <= S0;
              S0R_Ready <= '1';
            elsif (S1R_Valid='0') and (S0R_Valid='1') and (SR_Ready='0') then
              NextState <= Wait0;
              SR_Valid  <= '1';
              MuxSel    <= S0;
            end if;
          when Wait1 =>
            if (S1R_Valid='1') and (SR_Ready='1') then
              NextState <= MUX;
              SR_Valid  <= '1';
              MuxSel    <= S1;
              S1R_Ready <= '1';
            elsif (S1R_Valid='1') and (SR_Ready='0') then
              NextState <= Wait1;
              SR_Valid  <= '1';
              MuxSel    <= S1;
            end if;
          when Wait0 =>
            if (S0R_Valid='1') and (SR_Ready='1') then
              NextState <= MUX;
              SR_Valid  <= '1';
              MuxSel    <= S0;
              S0R_Ready <= '1';
            elsif (S0R_Valid='1') and (SR_Ready='0') then
              NextState <= Wait0;
              SR_Valid  <= '1';
              MuxSel    <= S0;
            end if;
          when Err    => null;
          --when others => null;
        end case;
      end if;
    end process;

    StateReg: process(CLK)
		begin
		  if rising_edge(CLK) then
			  State <= NextState;
			end if;
		end process;
		
  end block;

  ReadySync: block
    signal Tmp_Valid   : std_logic := '0';
    signal Tmp_Channel : std_logic := '0';
    signal Tmp_ADR     : std_logic_vector(MEM_ldSIZE - 1 downto 1) := (others=>'0');
  begin
    
    RS_Valid   <= SR_Valid   when SR_Ready='1' else Tmp_Valid   when SR_Ready='0' else 'X';
    RS_Channel <= SR_Channel when SR_Ready='1' else Tmp_Channel when SR_Ready='0' else 'X';
    RS_ADR     <= SR_ADR     when SR_Ready='1' else Tmp_ADR     when SR_Ready='0' else (others=>'X');
    
    REGS: process(CLK)
    begin
      if rising_edge(CLK) then
        if RESET='1' then
          Tmp_Valid   <= '0';
          Tmp_Channel <= '-';
          Tmp_ADR     <= (others => '-');
          --
          SR_Ready    <= '0';
        elsif RESET='0' then
          if SR_Ready='1' then
            Tmp_Valid   <= SR_Valid;
            Tmp_Channel <= SR_Channel;
            Tmp_ADR     <= SR_ADR;
          end if;
          SR_Ready <= (not RS_Valid) or RS_Ready;
        else
          Tmp_Valid   <= 'X';
          Tmp_Channel <= 'X';
          Tmp_ADR     <= (others => 'X');
          --
          SR_Ready <= 'X';
        end if;
      end if;
    end process;
    
  end block;

  DS_DMUX: process(M0R_Ready, M1R_Ready, MR_Valid, MR_Channel, MR_DAT)
  begin
    M0R_Valid <= '0';
    M0R_DAT   <= (M0R_DAT'range => '-');
    M1R_Valid <= '0';
    M1R_DAT   <= (M1R_DAT'range => '-');
    MR_Ready  <= '0';
    if MR_Channel='0' then
      M0R_Valid <= MR_Valid;
      M0R_DAT   <= MR_DAT;
      MR_Ready  <= M0R_Ready;
    elsif MR_Channel='1' then
      M1R_Valid <= MR_Valid;
      M1R_DAT   <= MR_DAT;
      MR_Ready  <= M1R_Ready;
    end if;
  end process;

  Memory: process(CLK)
    variable read_lower_address : natural;
    variable read_upper_address : natural;
    variable write_address      : natural;
  begin
    if rising_edge(CLK) then
      -- memory read
      read_lower_address := to_integer( unsigned(RS_ADR(MEM_ldSIZE-1 downto 2))
                                      + unsigned(RS_ADR(1 downto 1)) );
      read_upper_address := to_integer( unsigned(RS_ADR(MEM_ldSIZE-1 downto 2)) );
      if RS_Ready='1' then
        X_upper <= upper_mem(read_upper_address);
        X_lower <= lower_mem(read_lower_address);
      end if;
      -- memory write
      write_address := to_integer(unsigned(SW_ADR));
      if SW_Valid='1' then
        for i in 0 to 1 loop
          if SW_SEL(i) = '1' then
            lower_mem(write_address)(i * 8 + 7 downto i * 8) <= SW_DAT (i * 8 + 7 downto i * 8);
          end if;
        end loop;
        for i in 2 to 3 loop
          if SW_SEL(i) = '1' then
            upper_mem(write_address)((i-2) * 8 + 7 downto (i-2) * 8) <= SW_DAT (i * 8 + 7 downto i * 8);
          end if;
        end loop;
      end if;
    end if;
  end process;

  DataSync: process(CLK)
  begin
    if rising_edge(CLK) then
      if RESET='1' then
        MR_Valid   <= '0';
        MR_Channel <= '0';
        Xchange    <= '0';
      elsif RS_Ready='1' then
        MR_Valid   <= RS_Valid;
        MR_Channel <= RS_Channel;
        Xchange    <= RS_ADR(1);
      end if;
    end if;
  end process;
  
  MR_DAT <= X_upper & X_lower when Xchange='0' else
            X_lower & X_upper when Xchange='1' else
            (others => '-');
  
  RS_Ready <= MR_Ready or (not MR_Valid);
  
  SW_Ready <= '1';

end arch;
