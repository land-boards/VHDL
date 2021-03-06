library ieee;
use ieee.std_logic_1164.all;
use  IEEE.STD_LOGIC_ARITH.all;
use  IEEE.STD_LOGIC_UNSIGNED.all;

ENTITY REG_8 IS PORT(
    clk : IN STD_LOGIC; -- clock.
    d   : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    ld  : IN STD_LOGIC; -- load/enable.
    clr : IN STD_LOGIC; -- async. clear.
    q   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0) -- output
);
END REG_8;

ARCHITECTURE description OF REG_8 IS

BEGIN
    process(clk, clr, ld)
    begin
        if clr = '1' then
            q <= x"00";
        elsif rising_edge(clk) then
            if ld = '1' then
                q <= d;
            end if;
        end if;
    end process;
END description;
