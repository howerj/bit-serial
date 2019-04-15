library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mem is 
	generic (
		asynchronous_reset: boolean  := true; -- use asynchronous reset if true, synchronous if false
		delay:              time     := 0 ns; -- simulation only, gate delay
		N:                  positive := 16);
	port (
		clk:         in std_ulogic;
		rst:         in std_ulogic;
		i, a:        in std_ulogic;
		o:          out std_ulogic;
   		oe, ie, ae:  in std_ulogic);
end;

architecture rtl of mem is
	signal a_c, a_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal i_c, i_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal o_c, o_n: std_ulogic_vector(N - 1 downto 0) := x"C001";
begin
	process (clk, rst)
	begin
		if rst = '1' and asynchronous_reset then
			a_c <= (others => '0'); -- parallel!
			i_c <= (others => '0'); -- parallel!
			o_c <= (others => '0'); -- parallel!
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				a_c <= (others => '0'); -- parallel!
				i_c <= (others => '0'); -- parallel!
				o_c <= (others => '0'); -- parallel!
			else
				a_c <= a_n;
				i_c <= i_n;
				o_c <= o_n;
			end if;
		end if;
	end process;


	process (a_c, i_c, o_c, i, a, oe, ie, ae)
	begin
		a_n <= a_c;
		i_n <= i_c;
		o_n <= o_c;
		o   <= o_c(0);
		if ae = '1' then a_n <= a      & a_c(a_c'high downto 1); end if;
		if oe = '1' then o_n <= o_c(0) & o_c(o_c'high downto 1); end if;
		if ie = '1' then i_n <= i      & i_c(i_c'high downto 1); end if;
	end process;
end architecture;

