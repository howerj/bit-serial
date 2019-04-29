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

architecture rtl of peripherals is
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
	-- tx    <= t_c after g.delay;
	io    <= a_c(a_c'high) = '1' and ae = '0' after g.delay;
	io_addr <= a_c(io_addr'range);
	ie_n  <= ie after g.delay;
	write <= true when (ie_c and (ie_c xor ie_n)) = '1' else false after g.delay;
	ld    <= ld_c after g.delay;
	o     <= o_c(0) after g.delay;
	tx_fifo_data <= i_c(tx_fifo_data'range);
	reg   <= i_c(reg'range);

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
			addr => a_n(a_n'high - 4 downto 0),
			dre  => dre,
			din  => i_n,
			dout => dout);

	process (clk, rst)
	begin
		if rst = '1' and g.asynchronous_reset then
			a_c  <= (others => '0') after g.delay; -- parallel!
			i_c  <= (others => '0') after g.delay; -- parallel!
			o_c  <= (others => '0') after g.delay; -- parallel!
			ld_c <= (others => '0') after g.delay; -- parallel!
			t_c  <= '0' after g.delay;
			ie_c <= '0' after g.delay;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				a_c  <= (others => '0') after g.delay; -- parallel!
				i_c  <= (others => '0') after g.delay; -- parallel!
				o_c  <= (others => '0') after g.delay; -- parallel!
				ld_c <= (others => '0') after g.delay; -- parallel!
				t_c  <= '0' after g.delay;
				ie_c <= '0' after g.delay;
			else
				a_c  <= a_n after g.delay;
				i_c  <= i_n after g.delay;
				o_c  <= o_n after g.delay;
				t_c  <= t_n after g.delay;
				ld_c <= ld_n after g.delay;
				ie_c <= ie_n after g.delay;
			end if;
		end if;
	end process;

	process (a_c, i_c, o_c, i, a, oe, ie, ae, t_c, ld_c, dout, io, write, sw, rx, io_addr,
		rx_fifo_data, rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full)
	begin
		a_n  <= a_c after g.delay;
		i_n  <= i_c after g.delay;
		o_n  <= o_c after g.delay;
		ld_n <= ld_c after g.delay;
		t_n  <= t_c after g.delay;
		o_n  <= dout after g.delay;
		dre  <= '1' after g.delay;
		dwe  <= '0' after g.delay;
		tx_fifo_we <= '0' after g.delay; 
		rx_fifo_re <= '0' after g.delay;
		clock_reg_tx_we <= '0' after g.delay;
		clock_reg_rx_we <= '0' after g.delay;
		control_reg_we <= '0' after g.delay;

		if ae = '1' then a_n <= a      & a_c(a_c'high downto 1) after g.delay; end if;
		if oe = '1' then o_n <= o_c(0) & o_c(o_c'high downto 1) after g.delay; end if;
		if ie = '1' then i_n <= i      & i_c(i_c'high downto 1) after g.delay; end if;

		if oe = '0' and ae = '0' then
			if io = false then
				dre <= '1' after g.delay;
			else
				o_n           <= (others => '0') after g.delay;
				case io_addr is
				when "000" => o_n(sw'range) <= sw after g.delay;
				when "001" =>
					o_n(7 downto 0) <= rx_fifo_data;
					o_n(8)          <= rx_fifo_empty;
					o_n(9)          <= rx_fifo_full;
					o_n(11)         <= tx_fifo_empty;
					o_n(12)         <= tx_fifo_full;
				when "010" =>
				when "011" =>
				when "100" =>
				when "101" =>
				when "110" =>
				when "111" =>
				when others =>
				end case;
				-- o_n(8)        <= rx after g.delay;
			end if;
		end if;

		if write and ae = '0' then
			if io = false then
				dwe <= '1' after g.delay;
			else
				case io_addr is
				when "000" => ld_n <= i_c(ld_c'range) after g.delay;
				when "001" => tx_fifo_we <= i_c(13) after g.delay; rx_fifo_re <= i_c(10) after g.delay;
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

