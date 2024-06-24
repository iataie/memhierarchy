library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Define the memory hierarchy components
-- RAM (Main Memory)

entity ram is
    generic (
        ADDR_WIDTH : natural := 12;  -- Address width in bits
        DATA_WIDTH : natural := 32;  -- Data width in bits
        DELAY      : natural := 5    -- Read/Write delay in clocks
    );
    port (
        clk      : in std_logic;
        addr     : in STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        data_in  : in STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        data_out : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        we       : in std_logic;
        cs       : in std_logic;
        ready    : out STD_LOGIC
    );
end entity;

architecture behavioral of ram is
    type ram_type is array (0 to 2**ADDR_WIDTH-1) of STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    signal ram_array : ram_type:=(others=>(others => '0'));
    signal count: integer := DELAY;
begin
    read_write:process(clk,we,cs)
    begin
        if rising_edge(clk) then
            if we = '1' and cs='1' then
                ram_array(CONV_INTEGER(addr)) <= data_in;
                ready <= '1';
            elsif cs='1' then
                data_out <= ram_array(CONV_INTEGER(addr));
                ready <= '1';
            end if;
        end if;
    end process;
end architecture;

--    delayed_readwrit :process(clk)
--    begin -- a inter counter for more daleys for example 4 clocks
--        report integer'image(count);
--        if rising_edge(clk)  then
--            if count=0 then
----                ready <= '1';
--                count <= DELAY;
--            else
--                count <= count-1;
--            end if;
--        end if;
--    end process;
--data_out <= ram_array(to_integer(addr));
