library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
--use IEEE.math_real.all;

-- Victim Cache
entity victim_cache is
    generic (
        ADDR_WIDTH       : natural := 12;   -- Address width in bits (cache index)
        DATA_WIDTH       : natural := 32;   -- Data width in bits
        CACHE_SIZE       : natural := 8;    -- Number of cache lines
        --CACHE_INDEX_SIZE : natural := natural(CEIL(LOG2(8.0))) --Number of bits for addressing Chache
        CACHE_INDEX_SIZE : natural := 3 --Number of bits for addressing Chache
    );
    port (
        clk      : in std_logic;
        addr     : in STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        data_in  : in STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        index_in : in STD_LOGIC_VECTOR(CACHE_INDEX_SIZE-1 downto 0);
        index_out: out STD_LOGIC_VECTOR(CACHE_INDEX_SIZE-1 downto 0);
        addr_evc : out STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);     -- address for the evicted line
        dirty_in : in STD_LOGIC;                                    -- dirty bit
        dirty_out: out STD_LOGIC;                                   -- dirty bit of current/selected line
        we       : in std_logic;
        wx       : in std_logic;                                    -- write to specific index (in swap operation with L1)?
        cs       : in std_logic;
        hit      : out std_logic;
        ready    : out STD_LOGIC
    );
end entity;

architecture behavioral of victim_cache is
    type cache_line_type is record
        valid   : std_logic;
        dirty   : std_logic;
        tag     : STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        data    : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    end record;
    type cache_type is array (0 to CACHE_SIZE-1) of cache_line_type;
    signal cache_array : cache_type:=(others=>(valid=> '0', dirty=>'0',tag=>(others=>'0'),data=>(others=>'0')));
    signal next_index: integer :=0;
begin
    writeCmd: process(clk,addr)
    variable i: integer;

    begin
        if rising_edge(clk)  and cs='1' and we='1' then
            if(wx = '1') then
                i := CONV_INTEGER(index_in);
                --hit <= '1';
            else
                i := next_index;
                next_index <= (next_index +1) mod CACHE_SIZE;
            end if;
            
            cache_array(i).valid <= '1';
            cache_array(i).dirty <= dirty_in;
            cache_array(i).data <= data_in;
            cache_array(i).tag  <= addr;
        end if;
    end process;
    
    readCmd:process(clk)
    begin
         -----------------------------------------------------------------------------------------------------------------
         -- provides some output (data+swap address(index)+ dirty bit of data line if controller wants to swap the line
         -- with l1 the victim line it knows them).
         -----------------------------------------------------------------------------------------------------------------
        if rising_edge(clk) and cs='1' and we='0' then
            for i in 0 to CACHE_SIZE-1 loop
                if CONV_INTEGER(addr) = CONV_INTEGER(cache_array(i).tag) and cache_array(i).valid = '1' then
                    data_out  <= cache_array(i).data;
                    index_out <= std_logic_vector(to_unsigned( i, index_out'length));
                    dirty_out <= cache_array(i).dirty;
                    hit <= '1';
                    exit;
                end if;
            end loop;
            
           -----------------------------------------------------------------------------------------------------------------
           -- provides some output (data+eviction address+ dirty bit of data line if controller wants to flash out the victim
           -- line to memory it knows them).
           -----------------------------------------------------------------------------------------------------------------
            hit <= '0';
            -- informs controller in case it needs to access memory (l1 miss) then it should write current line as provided
            dirty_out <= cache_array(next_index).dirty;  --write out dirty bit
            if(cache_array(next_index).dirty='1') then
                --if it is dirty then out addr/date pair for controller in L1 miss to write first this pair to mem.
                data_out <=  cache_array(next_index).data;
                addr_evc <=  cache_array(next_index).tag;
            end if;
        end if;
    end process;
end architecture;


--    readByIndexCmd: process(clk)
--    begin
--        if(cache_array(next_index).dirty='1' and cache_array(next_index).valid='1') then
--            data_out <= cache_array(i).data;
--            add_out <=  cache_array(i).tag;
--        end process;