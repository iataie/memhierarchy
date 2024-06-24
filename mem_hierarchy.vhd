library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;

-- Simulation config --std=02 --ieee=synopsys
-- Top-level memory hierarchy entity
entity mem_hierarchy is
    generic (
        ADDR_WIDTH          : natural := 12;    -- Address width in bits (cache index)
        DATA_WIDTH          : natural := 32;    -- Data width in bits
        VCACHE_SIZE         : natural := 8;     -- Number of victim cache lines
        L1CACHE_SIZE        : natural := 64;    -- Number of cache lines
        L1CACHE_INDEX_SIZE  : natural := 6;     -- Number of bits for addressing L1 Cache
        VCACHE_INDEX_SIZE   : natural := 3      -- Number of bits for addressing Victim Cache
    );
    port (
        clk      : in std_logic;
        addr     : in STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        data_in  : in STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        ready    : inout STD_LOGIC :='0';
        we       : in STD_LOGIC:='0';
        cs       : in STD_LOGIC:='0'
    );
end entity;

architecture behavioral of mem_hierarchy is
    component ram is
        port (
            clk      : in std_logic;
            addr     : in STD_LOGIC_VECTOR(11 downto 0);
            data_in  : in STD_LOGIC_VECTOR(31 downto 0);
            data_out : out STD_LOGIC_VECTOR(31 downto 0);
            we       : in std_logic;
            cs       : in STD_LOGIC;
            ready    : out STD_LOGIC
        );
    end component;

    component l1_cache is
        port (
            clk      : in  std_logic;
            addr     : in  STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
            addr_evc : out STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
            data_in  : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
            data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
            we_cpu   : in  std_logic;
            we_vic   : in  std_logic;
            we_mem   : in  std_logic;
            cs       : in  std_logic;
            hit      : out std_logic;
            dirty_in : in  STD_LOGIC;
            dirty_out: out STD_LOGIC;
            evicted  : out STD_LOGIC;
            ready    : out STD_LOGIC
        );
    end component;

    component victim_cache is
        port (
            clk      : in  std_logic;
            addr     : in  STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
            addr_evc : out STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
            data_in  : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
            data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
            index_in : in  STD_LOGIC_VECTOR(VCACHE_INDEX_SIZE-1 downto 0);
            index_out: out STD_LOGIC_VECTOR(VCACHE_INDEX_SIZE-1 downto 0);
            dirty_in : in  STD_LOGIC;
            dirty_out: out STD_LOGIC;
            we       : in  std_logic;
            wx       : in  std_logic;
            cs       : in  std_logic;
            hit      : out std_logic;
            ready    : out STD_LOGIC
        );
    end component;
        
    signal ram_we, l1_we_cpu,l1_we_vic,l1_we_mem, victim_we,ram_ready, l1_ready, victim_ready : std_logic;
    signal l1_addr : STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
    signal victim_addr : STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
    signal ram_addr : STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
    signal l1_data_input, victim_data_input : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    signal l1_addr_evc, victim_addr_evc : STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
    signal ram_data_input,ram_data_output,l1_data_output, victim_data_output : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    signal wait4ram: STD_LOGIC:='0';        -- handshake mechanism for ram (is waiting for ram)
    signal wait4l1_cache: STD_LOGIC:='0';   -- handshake mechanism for L1 (is waiting for l1)
    signal wait4v_cache: STD_LOGIC:='0';    -- handshake mechanism for Victim (is waiting for V)
    signal ram_cs  : STD_LOGIC:='0';
    signal l1_cs  : STD_LOGIC:='0';
    signal victim_cs  : STD_LOGIC:='0';
    signal l1_hit  : STD_LOGIC:='0';
    signal victim_hit  : STD_LOGIC:='0';
    signal l1_evicted : STD_LOGIC;
    signal l1_dirty_in, l1_dirty_out  : STD_LOGIC;
    signal victim_dirty_in, victim_dirty_out  : STD_LOGIC;
    SIGNAL index_in  : STD_LOGIC_VECTOR (VCACHE_INDEX_SIZE-1 downto 0);
    SIGNAL index_out : STD_LOGIC_VECTOR (VCACHE_INDEX_SIZE-1 downto 0);
    Signal wx : STD_LOGIC:= '0';
    type statetype is (S0_Init , S1_AcsL1V ,S2_L1EVCR,S3_L1EVCR,S4_L1EVCR,S2_SWAPR,S2_SWAPW,S2_L1HITR,S2_L1HITW,S2_L1EVCW, S3_L1EVCW,S2_L1EVCR1,S2_L1EVCW1);
    signal CurrentState: statetype:=S0_Init;
    signal NextState: statetype;
    
    function enum_to_string(enum : statetype) return string is
    begin
        case enum is
            when S0_Init    => return "S0_Init";
            when S1_AcsL1V  => return "S1_AcsL1V";
            when S2_L1EVCR  => return "S2_L1EVCR";
            when S3_L1EVCR  => return "S3_L1EVCR";
            when S4_L1EVCR  => return "S4_L1EVCR";
            when S2_SWAPR   => return "S2_SWAPR";
            when S2_SWAPW   => return "S2_SWAPW";
            when S2_L1HITR  => return "S2_L1HITR";
            when S2_L1HITW  => return "S2_L1HITW";
            when S2_L1EVCW  => return "S2_L1EVCW";
            when S3_L1EVCW  => return "S3_L1EVCW";
            when S2_L1EVCR1 => return "S2_L1EVCR1";
            when S2_L1EVCW1 => return "S2_L1EVCW1";
        end case;
    end function enum_to_string;
    
    procedure print(msg : string) is
        variable l : line;
    begin
        write(l, msg);
        writeline(output, l);
    end procedure;
begin
    
    -- Instantiate RAM, L1 Cache, and Victim Cache
    ram_inst : ram
    port map (
        clk      => clk,
        addr     => addr,               -- (ADDR_WIDTH-1 downto 0),
        data_in  => ram_data_input,
        data_out => ram_data_output,    -- open,
        we       => ram_we,
        cs       => ram_cs,
        ready    => ram_ready           -- ram_RDY  stall  ram_Din ram_Dout
    );

    l1_cache_inst : l1_cache
    port map (
        clk      => clk,
        addr     => l1_addr,
        data_in  => l1_data_input,
        data_out => l1_data_output,     --victim_cache_inst.data_in, -- open,
        we_cpu   => l1_we_cpu,
        we_vic   => l1_we_vic,
        we_mem   => l1_we_mem,
        cs       => l1_cs,
        hit      => l1_hit,
        dirty_in => l1_dirty_in,
        dirty_out=> l1_dirty_out,
        evicted  => l1_evicted,
        ready    => l1_ready
    );
    
    victim_cache_inst : victim_cache
    port map (
        clk      => clk,
        addr     => victim_addr,
        data_in  => victim_data_input,      -- open -- data_in,
        data_out =>  victim_data_output,    -- open,
        index_in => index_in,
        index_out => index_out,
        dirty_in => victim_dirty_in,
        dirty_out=> victim_dirty_out,
        addr_evc => victim_addr_evc,
        we       => victim_we,
        wx      => wx,
        cs       => victim_cs,
        hit      => victim_hit,
        ready    => victim_ready
    );


    StateTransitionProcess:process(CurrentState,l1_hit,victim_hit,l1_evicted,victim_dirty_out)
    
    begin
        case CurrentState is
            when S0_Init    => NextState <= S1_AcsL1V;
            when S1_AcsL1V  =>
                if l1_hit = '1' and we='0' then
                    NextState <= S2_L1HITR;
                elsif l1_hit = '1'  then
                    NextState <= S2_L1HITW;
                elsif victim_hit = '1' and we='0' then     -- and  victim_evicted = '0' then
                    NextState <= S2_SWAPR;
                elsif victim_hit = '1' then                -- and  victim_evicted = '0' then
                    NextState <= S2_SWAPW;
                elsif  l1_evicted= '1' and victim_dirty_out = '1' and we ='0' then -- for read victim_hit = '0' and l1_hit = '0'
                    NextState <= S2_L1EVCR;
                elsif  l1_evicted= '1' and victim_dirty_out = '1'  then -- for write victim_hit = '0' and l1_hit = '0'
                    NextState <= S2_L1EVCW;
                elsif l1_evicted= '1' and we='0' then
                    NextState <= S2_L1EVCR1;
                elsif l1_evicted= '1' and we='1' then
                    NextState <= S2_L1EVCW1;
                elsif l1_evicted/='1' and we='0' then  -- S2_L1MISS
                    NextState <= S3_L1EVCR;
                elsif l1_evicted/='1' and we='1' then  -- S2_L1MISS
                    NextState <= S0_Init;
                end if;
            when S2_L1EVCR  => NextState <= S3_L1EVCR;
            when S2_L1EVCW  => NextState <= S3_L1EVCW;
            when S2_L1HITR  => NextState <= S0_Init;
            when S2_L1HITW  => NextState <= S0_Init;
            when S2_SWAPR   => NextState <= S0_Init;
            when S2_SWAPW   => NextState <= S0_Init;
            when S3_L1EVCR  => NextState <= S4_L1EVCR;
            when S4_L1EVCR  => NextState <= S0_Init;
            when S3_L1EVCW  => NextState <= S0_Init;
            when S2_L1EVCR1 => NextState <= S3_L1EVCR;
            when S2_L1EVCW1 => NextState <= S3_L1EVCW;
            when others     => null;
        end case;
    end process;
    SeqProcess:process(clk,cs) is

    begin        
        if falling_edge(clk) and (cs='1' or CurrentState/=S0_Init)  then
            CurrentState <= NextState;           
            report "State: " & enum_to_string(CurrentState);
        end if;
    end process SeqProcess;

    doState:process(CurrentState) is

    begin
        --report "ready: " & std_logic'image(ready) severity note;
        --print("ready: " & std_logic'image(ready));
        --reset signals
        ram_cs      <= '0';
        l1_cs       <= '0';
        l1_we_mem   <= '0';
        l1_we_cpu   <= '0';
        l1_we_vic   <= '0';
        victim_cs   <='0';
        wx          <= '0';
        
        if CurrentState=S0_Init then
            ready <= '1';
        elsif CurrentState=S1_AcsL1V then
            ready <= '0';               --<===============
            
            l1_cs       <= '1';
            victim_cs   <= '1';
            
            l1_we_cpu   <= we;
            l1_we_vic   <= '0';
            l1_we_mem   <= '0';
            
            l1_addr     <= addr;
            l1_data_input <= data_in;
            --victim_we<=we;
            victim_we   <= '0';         -- try to read from victim though it is a write command to memeory
            victim_addr <= addr;
            
        elsif CurrentState=S2_L1HITR then
            data_out            <= l1_data_output;
            ready               <= '1';
        elsif CurrentState=S2_L1HITW then
            ready               <= '1';
        elsif CurrentState= S2_L1EVCR then
            victim_cs           <= '1';
            victim_we           <= '1';
            wx                  <= '0';        -- maybe useless
            victim_addr         <= l1_addr_evc;
            victim_data_input   <= l1_data_output;
            victim_dirty_in     <= l1_dirty_out;
            
            -- write evicted line of victim cache into ram
            ram_cs              <= '1';
            ram_we              <= '1';
            ram_addr            <= victim_addr_evc;
            ram_data_input      <= victim_data_output;
        elsif CurrentState = S3_L1EVCR then
            ram_cs              <= '1';
            ram_we              <= '0';
            ram_addr            <= addr;
        elsif CurrentState = S4_L1EVCR then
            --ram_cs <= '0';
            l1_cs               <= '1';
            l1_we_mem           <= '1';
            l1_data_input       <= ram_data_output;
            
            data_out            <= ram_data_output;
            ready               <= '1';
        elsif CurrentState = S2_SWAPR then
            -- L1 ==> Victim
            victim_we           <= '1';
            wx                  <= '1';
            index_in            <= index_out;
            victim_addr         <= L1_addr_evc;
            victim_data_input   <= L1_data_output;
            victim_dirty_in     <= l1_dirty_out;
            
            -- Victim ==> L1 and cpu
            l1_cs               <= '1';
            l1_we_vic           <= '1';
            l1_addr             <= addr;
            l1_data_input       <= victim_data_output;
            l1_dirty_in         <= victim_dirty_out;
            
            data_out            <= victim_data_output;
            ready               <= '1';
        elsif CurrentState = S2_SWAPW then
            -- L1 ==> Victim
            victim_we           <= '1';
            wx                  <= '1';
            index_in            <= index_out;
            victim_addr         <= L1_addr_evc;
            victim_data_input   <= L1_data_output;
            victim_dirty_in     <= l1_dirty_out;
            
            -- Victim ==> L1
            l1_cs               <= '1';
            l1_we_vic           <= '1';
            l1_addr             <= addr;
            l1_data_input       <= data_in;
            l1_dirty_in         <= '1';
            
            ready               <= '1';
        elsif CurrentState= S2_L1EVCW then
            victim_cs           <= '1';
            victim_we           <= '1';
            wx                  <= '0';        -- maybe useless
            victim_addr         <= l1_addr_evc;
            victim_data_input   <= l1_data_output;
            victim_dirty_in     <= l1_dirty_out;
            
            -- write evicted line of victim cache into ram
            ram_cs              <= '1';
            ram_we              <= '1';
            ram_addr            <= victim_addr_evc;
            ram_data_input      <= victim_data_output;
        elsif CurrentState = S3_L1EVCW then
            l1_cs               <= '1';
            l1_we_cpu           <= '1';
            l1_addr             <= addr;
            l1_data_input       <= data_in;
            l1_dirty_in         <= '1';
            
            ready               <= '1';
            
        elsif CurrentState= S2_L1EVCR1 then
            victim_cs           <= '1';
            victim_we           <= '1';
            wx                  <= '0';        -- maybe useless
            victim_addr         <= l1_addr_evc;
            victim_data_input   <= l1_data_output;
            victim_dirty_in     <= l1_dirty_out;
            
        elsif CurrentState= S2_L1EVCW1 then
            victim_cs           <= '1';
            victim_we           <= '1';
            wx                  <= '0';        -- maybe useless
            victim_addr         <= l1_addr_evc;
            victim_data_input   <= l1_data_output;
            victim_dirty_in     <= l1_dirty_out;
        end if;
    end process;
end architecture;
