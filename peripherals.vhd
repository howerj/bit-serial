-- File:        peripherals.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- License:     MIT
-- Description: Memory and Memory mapped peripherals

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.util.all;
use work.uart_pkg.all;

entity peripherals is 
	generic (
		g:          common_generics;
		file_name:  string;
		W:          positive;
		N:          positive);
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

architecture rtl of peripherals is
	constant data_length: positive := N;
	constant addr_length: positive := W;

	type registers_t is record
		a:  std_ulogic_vector(N - 1 downto 0);
		i:  std_ulogic_vector(N - 1 downto 0);
		o:  std_ulogic_vector(N - 1 downto 0);
		ld: std_ulogic_vector(ld'range);
		ie: std_ulogic;
	end record;

	constant registers_default: registers_t := (
		a  => (others => '0'),
		i  => (others => '0'),
		o  => (others => '0'),
		ld => (others => '0'),
		ie => '0'
	);

	signal c, f: registers_t := registers_default;

	signal io,   write: boolean    := false;
	signal dwe,    dre: std_ulogic := '0';
	signal dout: std_ulogic_vector(N - 1 downto 0) := (others => '0');

	signal tx_fifo_full:  std_ulogic;
	signal tx_fifo_empty: std_ulogic;
	signal tx_fifo_we:    std_ulogic;
	signal tx_fifo_data:  std_ulogic_vector(7 downto 0);

	signal rx_fifo_full:  std_ulogic;
	signal rx_fifo_empty: std_ulogic;
	signal rx_fifo_re:    std_ulogic;
	signal rx_fifo_data:  std_ulogic_vector(7 downto 0);

	signal reg:             std_ulogic_vector(15 downto 0);
	signal clock_reg_tx_we: std_ulogic;
	signal clock_reg_rx_we: std_ulogic;
	signal control_reg_we:  std_ulogic;

	signal io_addr: std_ulogic_vector(2 downto 0);
begin
	-- tx    <= c.c after g.delay;
	io    <= c.a(c.a'high) = '1' and ae = '0' after g.delay;
	io_addr <= c.a(io_addr'range);
	write <= true when (c.ie and (c.ie xor f.ie)) = '1' else false after g.delay;
	ld    <= c.ld after g.delay;
	o     <= c.o(0) after g.delay;
	tx_fifo_data <= c.i(tx_fifo_data'range);
	reg   <= c.i(reg'range);

	-- TODO: Selected between raw UART pin input/output and the UART module
	-- with a generic. This will allow a bit-banged UART driver to be developed.
	-- This same UART module could be used in the test bench to test that driver.
	uart: entity work.uart_top
		generic map (g => g)
		port map(
			clk => clk, rst => rst, 

			tx               =>  tx,
			tx_fifo_full     =>  tx_fifo_full,
			tx_fifo_empty    =>  tx_fifo_empty,
			tx_fifo_we       =>  tx_fifo_we,
			tx_fifo_data     =>  tx_fifo_data,

			rx               =>  rx,
			rx_fifo_full     =>  rx_fifo_full,
			rx_fifo_empty    =>  rx_fifo_empty,
			rx_fifo_re       =>  rx_fifo_re,
			rx_fifo_data     =>  rx_fifo_data,

			reg              =>  reg,
			clock_reg_tx_we  =>  clock_reg_tx_we,
			clock_reg_rx_we  =>  clock_reg_rx_we,
			control_reg_we   =>  control_reg_we);

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
			addr => f.a(f.a'high - 4 downto 0),
			dre  => dre,
			din  => f.i,
			dout => dout);

	process (clk, rst)
	begin
		if rst = '1' and g.asynchronous_reset then
			c <= registers_default after g.delay;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				c <= registers_default after g.delay;
			else
				c <= f after g.delay;
			end if;
		end if;
	end process;

	process (c, i, a, oe, ie, ae, dout, io, write, sw, rx, io_addr,
		rx_fifo_data, rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full)
	begin
		f    <= c after g.delay;
		f.o  <= dout after g.delay;
		f.ie <= ie after g.delay;
		dre  <= '1' after g.delay;
		dwe  <= '0' after g.delay;
		tx_fifo_we <= '0' after g.delay; 
		rx_fifo_re <= '0' after g.delay;
		clock_reg_tx_we <= '0' after g.delay;
		clock_reg_rx_we <= '0' after g.delay;
		control_reg_we <= '0' after g.delay;

		if ae = '1' then f.a <= a      & c.a(c.a'high downto 1) after g.delay; end if;
		if oe = '1' then f.o <= c.o(0) & c.o(c.o'high downto 1) after g.delay; end if;
		if ie = '1' then f.i <= i      & c.i(c.i'high downto 1) after g.delay; end if;

		if oe = '0' and ae = '0' then
			if io = false then
				dre <= '1' after g.delay;
			else
				f.o           <= (others => '0') after g.delay;
				case io_addr is
				when "000" => f.o(sw'range) <= sw after g.delay;
				when "001" =>
					f.o(7 downto 0) <= rx_fifo_data;
					f.o(8)          <= rx_fifo_empty;
					f.o(9)          <= rx_fifo_full;
					f.o(11)         <= tx_fifo_empty;
					f.o(12)         <= tx_fifo_full;
				when "010" =>
				when "011" =>
				when "100" =>
				when "101" =>
				when "110" =>
				when "111" =>
				when others =>
				end case;
				-- f.o(8)        <= rx after g.delay;
			end if;
		end if;

		if write and ae = '0' then
			if io = false then
				dwe <= '1' after g.delay;
			else
				case io_addr is
				when "000" => f.ld <= c.i(c.ld'range) after g.delay;
				when "001" => tx_fifo_we <= c.i(13) after g.delay; rx_fifo_re <= c.i(10) after g.delay;
				when "010" => clock_reg_tx_we <= '1' after g.delay;
				when "011" => clock_reg_rx_we <= '1' after g.delay;
				when "100" => control_reg_we <= '1' after g.delay;
				when "101" =>
				when "110" =>
				when "111" =>
				when others =>
				end case;
			end if;
		end if;
	end process;
end architecture;

