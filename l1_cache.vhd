--  --std=02 --ieee=synopsys
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.std_logic_textio.all;

-- L1 Cache
entity l1_cache is
    generic (
        ADDR_WIDTH : natural := 12;  -- Address width in bits (cache index)
        DATA_WIDTH : natural := 32;  -- Data width in bits
        CACHE_SIZE : natural := 64   -- Number of cache lines
    );
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
end entity;

architecture behavioral of l1_cache is
    type cache_line_type is record
        valid   : std_logic;
        dirty   : std_logic;
        tag     : STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        data    : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    end record;
    type cache_type is array (0 to CACHE_SIZE-1) of cache_line_type;
    signal cache_array : cache_type:=(others=>(valid=> '0', dirty=>'0',tag=>(others=>'0'),data=>(others=>'0')));

begin
    process(clk,addr,data_in)
    variable selected: integer;
    begin
        if rising_edge(clk)  and cs='1' then
            selected := CONV_INTEGER(addr(5 downto 0));
            if we_vic = '1' then                -- ***** victim path *****
                cache_array(selected).valid     <= '1';
                cache_array(selected).dirty     <= dirty_in;
                cache_array(selected).data      <= data_in;
                cache_array(selected).tag       <= addr;
                evicted                         <= '0';  -- could be redundant
                hit                             <= '0';  -- useless
            elsif we_mem = '1' then             -- ***** memory path *****
                cache_array(selected).valid     <= '1';
                cache_array(selected).dirty     <= '0';
                cache_array(selected).data      <= data_in;
                cache_array(selected).tag       <= addr;
                evicted                         <= '0';  -- could be redundant
                hit                             <= '0';  -- useless
                report "Fill L1 from mem => index:" & INTEGER'image(selected);
            elsif we_cpu = '1' and CONV_INTEGER(addr) = CONV_INTEGER(cache_array(selected).tag)  then
                cache_array(selected).valid     <= '1';
                cache_array(selected).dirty     <= dirty_in;
                cache_array(selected).data      <= data_in;
                cache_array(selected).tag       <= addr;
                evicted                         <= '0';  -- could be redundant
                hit                             <= '1';
                report "l1(hit) on write => Index:" & INTEGER'image(selected) & " valid:"& std_logic'image(cache_array(selected).valid) & " addr:" &to_hstring(addr)
                & " Data:" & to_hstring(cache_array(selected).data) & "(old)->" & to_hstring(data_in)&"(new)" severity  note;
            elsif we_cpu = '1' then             -- try to write on line; if valid=1 then evicts to victim cache else no eviction
                data_out                        <= cache_array(selected).data;
                addr_evc                        <= cache_array(selected).tag;
                evicted                         <= cache_array(selected).valid;
                dirty_out                       <= cache_array(selected).dirty;
                hit                             <= '0';
                cache_array(selected).data      <= data_in;  -- could be split here: write forced='0'(top lines) and foreced='1'(bottom lines)
                cache_array(selected).tag       <= addr;
                cache_array(selected).dirty     <= '1';
                cache_array(selected).valid     <= '1';
                report "l1(miss) on write " & INTEGER'image(selected) & "  "& std_logic'image(cache_array(selected).valid);
                --report "--->" & std_logic'image(cache_array(selected).valid);
            elsif we_cpu = '0' and CONV_INTEGER(addr) = CONV_INTEGER(cache_array(selected).tag) and cache_array(selected).valid='1' then
                data_out                        <= cache_array(selected).data;
                evicted                         <= '0';  -- could be redundant
                hit                             <= '1';
                report "L1(hit) on read=> Index:" & INTEGER'image(selected) & " ,Data:" & to_hstring(cache_array(selected).data);
                --report "++++>" & std_logic'image(cache_array(selected).valid);
                --data_out <= (0=>'1', others=>'0');  --to_integer(addr(5 downto 0))
            elsif we_cpu = '0' and CONV_INTEGER(addr) /= CONV_INTEGER(cache_array(selected).tag) then
                data_out                        <= cache_array(selected).data;
                addr_evc                        <= cache_array(selected).tag;
                evicted                         <= cache_array(selected).valid;
                dirty_out                       <= cache_array(selected).dirty;
                hit                             <= '0';
                report std_logic'image(cache_array(selected).valid);
            end if;
        end if;
    end process;
end architecture;

--    process(clk)
--    begin
--        if rising_edge(clk) then
--            for i in 0 to CACHE_SIZE-1 loop
--                if addr = cache_array(i).tag and cache_array(i).valid = '1' then
--                    data_out <= cache_array(i).data;
--                end if;
--            end loop;
--        end if;
--    end process;