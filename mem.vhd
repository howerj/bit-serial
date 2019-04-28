-- TODO: Rename to 'ad' for 'address decoder'
library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.util.all;

entity mem is 
	generic (
		g: common_generics;
		file_name:          string;
		W:                  positive;
		N:                  positive);
	port (
		clk:         in std_ulogic;
		rst:         in std_ulogic;
		rx:          in std_ulogic;
		tx:         out std_ulogic;
		ld:         out std_ulogic_vector(7 downto 0);
		sw:          in std_ulogic_vector(7 downto 0);
		i, a:        in std_ulogic;
		o:          out std_ulogic;
   		oe, ie, ae:  in std_ulogic);
end;

architecture rtl of mem is
	constant data_length: positive := N;
	constant addr_length: positive := W;
	signal a_c,    a_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal i_c,    i_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal o_c,    o_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal ld_c,  ld_n: std_ulogic_vector(ld'range)       := (others => '0');
	signal t_c,    t_n: std_ulogic := '0';
	signal ie_c,  ie_n: std_ulogic := '0';
	signal io,   write: boolean    := false;
	signal dwe,    dre: std_ulogic := '0';
	signal dout: std_ulogic_vector(N - 1 downto 0) := (others => '0');
begin
	tx    <= t_c;
	io    <= a_c(a_c'high) = '1' and ae = '0';
	ie_n  <= ie;
	write <= true when (ie_c and (ie_c xor ie_n)) = '1' else false;
	ld    <= ld_c;

	bram: entity work.single_port_block_ram
		generic map(
			g           => g,
			file_name   => file_name,
			file_type   => FILE_HEX,
			addr_length => addr_length,
			data_length => data_length)
		port map (
			clk  => clk,
			dwe  => dwe,
			addr => a_n(a_n'high - 4 downto 0),
			dre  => dre,
			din  => i_n,
			dout => dout);

	process (clk, rst)
	begin
		if rst = '1' and g.asynchronous_reset then
			a_c  <= (others => '0'); -- parallel!
			i_c  <= (others => '0'); -- parallel!
			o_c  <= (others => '0'); -- parallel!
			ld_c <= (others => '0'); -- parallel!
			t_c  <= '0';
			ie_c <= '0';
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				a_c  <= (others => '0'); -- parallel!
				i_c  <= (others => '0'); -- parallel!
				o_c  <= (others => '0'); -- parallel!
				ld_c <= (others => '0'); -- parallel!
				t_c  <= '0';
				ie_c <= '0';
			else
				a_c  <= a_n;
				i_c  <= i_n;
				o_c  <= o_n;
				t_c  <= t_n;
				ld_c <= ld_n;
				ie_c <= ie_n;
				dre  <= '1';
				dwe  <= '0';

				if oe = '0' and ae = '0' then
					if io = false then
						dre <= '1';
					else
						o_c           <= (others => '0');
						o_c(sw'range) <= sw;
						o_c(8)        <= rx;
					end if;
				end if;

				if write and ae = '0' then
					if io = false then
						dwe <= '1';
					else
						ld_c <= i_c(ld_c'range);
						t_c  <= i_c(8);
					end if;
				end if;
			end if;
		end if;
	end process;

	o    <= o_c(0);
	process (a_c, i_c, o_c, i, a, oe, ie, ae, t_c, ld_c, dout)
	begin
		a_n  <= a_c;
		i_n  <= i_c;
		o_n  <= o_c;
		ld_n <= ld_c;
		t_n  <= t_c;
		o_n  <= dout;

		if ae = '1' then a_n <= a      & a_c(a_c'high downto 1); end if;
		if oe = '1' then o_n <= o_c(0) & o_c(o_c'high downto 1); end if;
		if ie = '1' then i_n <= i      & i_c(i_c'high downto 1); end if;

	end process;
end architecture;

