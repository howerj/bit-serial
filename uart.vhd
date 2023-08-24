-- FILE:      uart.vhd
-- BRIEF:     UART TX/RX module
-- EMAIL:     howe.r.j.89@gmail.com
-- LICENSE:   MIT
-- COPYRIGHT: Richard James Howe (2019, 2020)
--
-- The UART (Universal Asynchronous Receiver/Transmitter) is one of the simplest
-- serial communication methods available. It is often used for debugging, for
-- issuing commands to embedded devices and sometimes even for uploading firmware
-- to devices. The data format and speed are configurable but there is no method
-- for automatically configuring a UART, both sides must have agreed on the
-- settings before hand. Configurable options include; baud, use of an
-- even of odd parity bit, number of data bits and number of stop bits.
--
-- The clock is not transmitted as part of the signal (which is why baud
-- must be agreed upon before hand), a single packet starts with a 'start bit',
-- where the line goes low. The receiver must synchronize to this start bit (it
-- resets the clock that generates pulse at the sample rate and baud when it
-- encounters a start bit).
--
-- A transmission with 8 data bits, 1 parity bit and 1 stop bit looks like
-- this:
-- ____   ______________________________   ________________
--     \_/|0|1|2|3|4|5|6|7|P|S|         \_/
--     Start   Data     Parity Stop    |--- More data --->
--
-- Start bits are always low, stop bits high. The most common format is
-- 8 data bits, no parity bit, and 1 stop bit at either 9600 or 115200 baud.
--
-- For the receiver a clock that is a multiple of the baud is used so the
-- bits can be sampled with a higher frequency than the bit rate.
--
-- Some notes:
--
-- * We can transmit from an 8-bit UART to a less than 8-bit UART fine, so
-- long as parity is not used (just set the high bits to 1).
-- * Certain UARTs have the ability to transmit a BREAK signal by holding
-- the line low for a period greater than the packet length. We can transmit
-- that by lowering the baud rate and transmitting all zeroes. Receiving a
-- break (correctly) would require changing the receiver.
--
--
-- See:
-- * <https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter>
--
-- NOTE: We could replace this entire package with an entirely software driven
-- solution. The only hardware we would need two timers driven at the sample
-- rate (one for RX, one for TX) and a deglitched RX signal. An interrupt
-- would be generated on the timers expiry.
--
library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package uart_pkg is
	constant uart_8N1: std_ulogic_vector(7 downto 0) := "10000100";

	type uart_generics is record
		clock_frequency:    positive; -- clock frequency of module clock
		delay:              time;     -- gate delay for simulation purposes
		asynchronous_reset: boolean;  -- use asynchronous reset if true
	end record;

	component uart_tx is
		generic (
			g:       uart_generics;
			N:       positive;
			format:  std_ulogic_vector(7 downto 0) := uart_8N1;
			use_cfg: boolean);
		port (
			clk:    in std_ulogic;
			rst:    in std_ulogic;
			cr:    out std_ulogic;
			baud:   in std_ulogic; -- Pulse at baud
			tx:    out std_ulogic;
			ok:    out std_ulogic;
			ctr:    in std_ulogic_vector(format'range);
			ctr_we: in std_ulogic;
			we:     in std_ulogic; -- di write enable
			di:     in std_ulogic_vector(N - 1 downto 0));
	end component;

	component uart_rx is
		generic (
			g:       uart_generics;
			N:       positive;
			D:       positive;
			format:  std_ulogic_vector(7 downto 0) := uart_8N1;
			use_cfg: boolean);
		port (
			clk:     in std_ulogic;
			rst:     in std_ulogic;
			cr:     out std_ulogic;
			baud:    in std_ulogic;
			sample:  in std_ulogic;
			failed: out std_ulogic_vector(1 downto 0);
			ctr:     in std_ulogic_vector(7 downto 0);
			ctr_we:  in std_ulogic;
			rx:      in std_ulogic;
			we:     out std_ulogic;
			do:     out std_ulogic_vector(N - 1 downto 0));
	end component;

	component uart_fifo is
		generic (
			g:           uart_generics;
			data_width:  positive;
			fifo_depth:  positive;
			read_first:  boolean := true);
		port (
			clk:   in  std_ulogic;
			rst:   in  std_ulogic;
			di:    in  std_ulogic_vector(data_width - 1 downto 0);
			we:    in  std_ulogic;
			re:    in  std_ulogic;
			do:    out std_ulogic_vector(data_width - 1 downto 0);

			-- optional
			full:  out std_ulogic := '0';
			empty: out std_ulogic := '1');
	end component;

	component uart_baud is -- Generates a pulse at the sample rate and baud
		generic (
			g:    uart_generics;
			init: integer;
			N:    positive := 16;
			D:    positive := 3);
		port (
			clk:      in std_ulogic;
			rst:      in std_ulogic;
			we:       in std_ulogic;
			cnt:      in std_ulogic_vector(N - 1 downto 0);
			cr:       in std_ulogic := '0';
			sample:  out std_ulogic;
			baud:    out std_ulogic);
	end component;

	component uart_top is
		generic (
			clock_frequency:    positive; -- clock frequency of module clock
			delay:              time;     -- gate delay for simulation purposes
			asynchronous_reset: boolean;  -- use asynchronous reset if true
			baud:               positive := 115200;
			format:             std_ulogic_vector(7 downto 0) := uart_8N1;
			fifo_depth:         natural := 0;
			use_cfg:            boolean := false;
			use_tx:             boolean := true;
			use_rx:             boolean := true
			); -- Use FIFO to buffer results?
		port (
			clk:    in std_ulogic;
			rst:    in std_ulogic;

			tx:            out std_ulogic;
			tx_fifo_full:  out std_ulogic;
			tx_fifo_empty: out std_ulogic;
			tx_fifo_we:     in std_ulogic;
			tx_fifo_data:   in std_ulogic_vector(7 downto 0);

			rx:             in std_ulogic;
			rx_fifo_full:  out std_ulogic;
			rx_fifo_empty: out std_ulogic;
			rx_fifo_re:     in std_ulogic;
			rx_fifo_data:  out std_ulogic_vector(7 downto 0);

			reg:             in std_ulogic_vector(15 downto 0);
			clock_reg_tx_we: in std_ulogic;
			clock_reg_rx_we: in std_ulogic;
			control_reg_we:  in std_ulogic);
	end component;

	component uart_tb is
		generic(g: uart_generics);
	end component;

	function parity(slv:std_ulogic_vector; even: boolean) return std_ulogic;
	function parity(slv:std_ulogic_vector; even: std_ulogic) return std_ulogic;
	constant ctr_use_parity:  integer := 0;
	constant ctr_even_parity: integer := 1;
	function ctr_stop_bits(ctr: std_ulogic_vector(7 downto 0)) return integer;
	function ctr_data_bits(ctr: std_ulogic_vector(7 downto 0)) return integer;
end package;

package body uart_pkg is
	function parity(slv: std_ulogic_vector; even: boolean) return std_ulogic is
		variable z: std_ulogic := '0';
	begin
		if not even then
			z := '1';
		end if;
		for i in slv'range loop
			z := z xor slv(i);
		end loop;
		return z;
	end;

	function parity(slv:std_ulogic_vector; even: std_ulogic) return std_ulogic is
		variable z: boolean := false;
	begin
		if even = '1' then
			z := true;
		end if;
		return parity(slv, z);
	end;

	function ctr_stop_bits(ctr: std_ulogic_vector(7 downto 0)) return integer is
		variable ii: std_ulogic_vector(1 downto 0);
	begin
		ii := ctr(3 downto 2);
		return to_integer(unsigned(ii));
	end function;

	function ctr_data_bits(ctr: std_ulogic_vector(7 downto 0)) return integer is
		variable ii: std_ulogic_vector(3 downto 0);
	begin
		ii := ctr(7 downto 4);
		return to_integer(unsigned(ii));
	end function;
end;

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_top is
	generic (
		clock_frequency:    positive; -- clock frequency of module clock
		delay:              time;     -- gate delay for simulation purposes
		asynchronous_reset: boolean;  -- use asynchronous reset if true
		baud:               positive := 115200;
		format:             std_ulogic_vector(7 downto 0) := uart_8N1;
		fifo_depth:         natural := 0; -- FIFO depth, 0,1 = no FIFO
		use_cfg:            boolean := false; -- allow run time configuration of baud rate and format?
		use_tx:             boolean := true;  -- instantiate TX functionality?
		use_rx:             boolean := true   -- instantiate RX functionality?
	);
	port (
		clk:    in std_ulogic;
		rst:    in std_ulogic;

		tx:            out std_ulogic;
		tx_fifo_full:  out std_ulogic;
		tx_fifo_empty: out std_ulogic;
		tx_fifo_we:     in std_ulogic;
		tx_fifo_data:   in std_ulogic_vector(7 downto 0);

		rx:             in std_ulogic;
		rx_fifo_full:  out std_ulogic;
		rx_fifo_empty: out std_ulogic;
		rx_fifo_re:     in std_ulogic;
		rx_fifo_data:  out std_ulogic_vector(7 downto 0);

		reg:             in std_ulogic_vector(15 downto 0);
		clock_reg_tx_we: in std_ulogic;
		clock_reg_rx_we: in std_ulogic;
		control_reg_we:  in std_ulogic);
end entity;

architecture structural of uart_top is
	constant g: uart_generics := (
		clock_frequency => clock_frequency,
		delay => delay,
		asynchronous_reset => asynchronous_reset
	);
	constant tx_init: integer  := g.clock_frequency / (baud * 16); -- 54 = 115200 @ 100 MHz
	constant rx_init: positive := tx_init - 1; -- 50 = 115200 @ 100 MHz + Fudge Factor
	constant N: positive := 8;

	signal rx_ok, rx_nd, rx_push, rx_re: std_ulogic := '0';
	signal rx_pushed: std_ulogic_vector(rx_fifo_data'range) := (others => '0');
	signal tx_pop, tx_ok: std_ulogic := '0';
	signal tx_popped: std_ulogic_vector(tx_fifo_data'range) := (others => '0');
	signal tx_fifo_empty_b, rx_fifo_full_b: std_ulogic := '0';

	signal tx_sample, tx_baud, tx_cr: std_ulogic := '0';
	signal rx_sample, rx_baud, rx_cr, rx_we: std_ulogic := '0';
	signal rx_fail: std_ulogic_vector(1 downto 0) := (others => '0');
	signal rx_ok_buf: std_ulogic := '0';
	signal do, do_c, do_n: std_ulogic_vector(rx_fifo_data'range) := (others => '0');
	signal fail_c, fail_n: std_ulogic_vector(1 downto 0) := (others => '0');
	signal nd_c, nd_n: std_ulogic := '0'; -- new data

begin
	rx_ok_buf <= not (fail_c(0) or fail_c(1)) after g.delay;
	rx_ok <= rx_ok_buf;
	rx_pushed <= do after g.delay;
	rx_nd <= nd_c and rx_ok_buf after g.delay; -- no new data if there are errors
	rx_re <= rx_push;

	process (clk, rst)
	begin
		if use_rx then
			if rst = '1' and g.asynchronous_reset then
				do_c   <= (others => '0') after g.delay;
				fail_c <= (others => '0') after g.delay;
				nd_c   <= '0' after g.delay;
			elsif rising_edge(clk) then
				if rst = '1' and not g.asynchronous_reset then
					do_c   <= (others => '0') after g.delay;
					fail_c <= (others => '0') after g.delay;
					nd_c   <= '0' after g.delay;
				else
					do_c <= do_n     after g.delay;
					nd_c <= nd_n     after g.delay;
					fail_c <= fail_n after g.delay;
				end if;
			end if;
		end if;
	end process;

	process (do_c, do, nd_c, rx_we, rx_re, fail_c, rx_fail)
	begin
		if use_tx then
			do_n   <= do_c   after g.delay;
			nd_n   <= nd_c   after g.delay;
			fail_n <= fail_c after g.delay;
			if rx_we = '1' then
				nd_n   <= '1'     after g.delay;
				do_n   <= do      after g.delay;
				fail_n <= rx_fail after g.delay;
			elsif rx_re = '1' then
				nd_n   <= '0' after g.delay;
			end if;
		end if;
	end process;

	ugen0: if fifo_depth <= 1 generate
			tx_pop        <= tx_fifo_we;
			tx_popped     <= tx_fifo_data;
			tx_fifo_full  <= not tx_ok;
			tx_fifo_empty <= tx_ok;

			rx_push       <= rx_fifo_re;
			rx_fifo_data  <= rx_pushed;
			rx_fifo_full  <= rx_nd;
			rx_fifo_empty <= not rx_nd;
	end generate;

	ugen1: if fifo_depth > 1 generate
		tx_fifo_empty <=               tx_fifo_empty_b;
		tx_pop        <= tx_ok and not tx_fifo_empty_b;

		ugen1_fifo_tx: if use_tx generate
			uart_fifo_tx_0: work.uart_pkg.uart_fifo
				generic map(g => g,
					   data_width => tx_fifo_data'length,
					   fifo_depth => fifo_depth)
				port map (clk  => clk, rst => rst,
					  di   => tx_fifo_data,
					  we   => tx_fifo_we,
					  re   => tx_pop,
					  do   => tx_popped,
					  full => tx_fifo_full,
					  empty => tx_fifo_empty_b);
		end generate;

		rx_fifo_full <=                         rx_fifo_full_b;
		rx_push      <= rx_nd and rx_ok and not rx_fifo_full_b;
		ugen1_fifo_rx: if use_rx generate
			uart_fifo_rx_0: work.uart_pkg.uart_fifo
				generic map(g => g,
					   data_width => rx_fifo_data'length,
					   fifo_depth => fifo_depth,
					   read_first => false)
				port map (clk  => clk, rst => rst,
					  di   => rx_pushed,
					  we   => rx_push,
					  re   => rx_fifo_re,
					  do   => rx_fifo_data,
					  full => rx_fifo_full_b, empty => rx_fifo_empty);
		end generate;
	end generate;

	uart_tx_gen: if use_tx generate
		baud_tx: work.uart_pkg.uart_baud
			generic map(g => g, init => tx_init, N => reg'length, D => 3)
			port map(
				clk    => clk,
				rst    => rst,
				we     => clock_reg_tx_we,
				cnt    => reg,  -- 0x32/50 is 1152000 @ 100MHz clk
				cr     => tx_cr,
				sample => tx_sample,
				baud   => tx_baud);

		tx_0: work.uart_pkg.uart_tx
			generic map(g => g, N => N, format => format, use_cfg => use_cfg)
			port map(
				clk     => clk,
				rst     => rst,

				cr      => tx_cr,
				baud    => tx_baud,
				ok      => tx_ok,
				we      => tx_pop,
				ctr     => reg(reg'high downto reg'high - 7),
				ctr_we  => control_reg_we,
				di      => tx_popped,
				tx      => tx);
	end generate;

	uart_rx_gen: if use_rx generate
		baud_rx: work.uart_pkg.uart_baud
			generic map(g => g, init => rx_init, N => reg'length, D => 3)
			port map(
				clk    => clk,
				rst    => rst,
				we     => clock_reg_rx_we,
				cnt    => reg,
				cr     => rx_cr,
				sample => rx_sample,
				baud   => rx_baud);

		rx_0: work.uart_pkg.uart_rx
			generic map(g => g, N => N, D => 3, format => format, use_cfg => use_cfg)
			port map(
				clk     => clk,
				rst     => rst,

				baud    => rx_baud,
				sample  => rx_sample,
				cr      => rx_cr,
				failed  => rx_fail,
				ctr     => reg(reg'low + 7 downto reg'low),
				ctr_we  => control_reg_we,
				we      => rx_we,
				do      => do,
				rx      => rx);
	end generate;
end architecture;

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_fifo is
	generic (g: uart_generics;
		data_width: positive;
		fifo_depth: positive;
		read_first: boolean := true);
	port (
		clk:   in  std_ulogic;
		rst:   in  std_ulogic;
		di:    in  std_ulogic_vector(data_width - 1 downto 0);
		we:    in  std_ulogic;
		re:    in  std_ulogic;
		do:    out std_ulogic_vector(data_width - 1 downto 0);

		-- optional
		full:  out std_ulogic := '0';
		empty: out std_ulogic := '1');
end uart_fifo;

architecture behavior of uart_fifo is
	type fifo_data_t is array (0 to fifo_depth - 1) of std_ulogic_vector(di'range);
	signal data: fifo_data_t := (others => (others => '0'));
	function rindex_init return integer is
	begin
		if read_first then
			return 0;
		end if;
		return fifo_depth - 1;
	end function;

	signal count:  integer range 0 to fifo_depth := 0;
	signal windex: integer range 0 to fifo_depth - 1 := 0;
	signal rindex: integer range 0 to fifo_depth - 1 := rindex_init;

	signal is_full:  std_ulogic := '0';
	signal is_empty: std_ulogic := '1';
begin
	do       <= data(rindex) after g.delay;
	full     <= is_full after g.delay;  -- buffer these bad boys
	empty    <= is_empty after g.delay;
	is_full  <= '1' when count = fifo_depth else '0' after g.delay;
	is_empty <= '1' when count = 0          else '0' after g.delay;

	process (rst, clk) is
	begin
		if rst = '1' and g.asynchronous_reset then
			windex <= 0 after g.delay;
			count  <= 0 after g.delay;
			rindex <= rindex_init after g.delay;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				windex <= 0 after g.delay;
				count  <= 0 after g.delay;
				rindex <= rindex_init after g.delay;
			else
				if we = '1' and re = '0' then
					if is_full = '0' then
						count <= count + 1 after g.delay;
					end if;
				elsif we = '0' and re = '1' then
					if is_empty = '0' then
						count <= count - 1 after g.delay;
					end if;
				end if;

				if re = '1' and is_empty = '0' then
					if rindex = (fifo_depth - 1) then
						rindex <= 0 after g.delay;
					else
						rindex <= rindex + 1 after g.delay;
					end if;
				end if;

				if we = '1' and is_full = '0' then
					if windex = (fifo_depth - 1) then
						windex <= 0 after g.delay;
					else
						windex <= windex + 1 after g.delay;
					end if;
					data(windex) <= di after g.delay;
				end if;
			end if;
		end if;
	end process;
end behavior;

-- This module generates a sample pulse and a baud pulse. The sample rate
-- can be controlled by setting 'cnt'. This sample rate is then divided by
-- 2^(D+1) to get the baud.
library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_baud is
	generic (g: uart_generics; init: integer; N: positive := 16; D: positive := 3);
	port (
		clk:     in std_ulogic;
		rst:     in std_ulogic;

		we:      in std_ulogic;
		cnt:     in std_ulogic_vector(N - 1 downto 0);
		cr:      in std_ulogic := '0';

		sample: out std_ulogic;  -- sample pulse
		baud:   out std_ulogic); -- baud (sample rate / 2^(D+1))
end entity;

architecture behaviour of uart_baud is
	constant cmp_init: std_ulogic_vector := std_ulogic_vector(to_unsigned(init, cnt'length));
	signal cmp_c, cmp_n: std_ulogic_vector(cnt'range)  :=  cmp_init;
	signal cnt_c, cnt_n: std_ulogic_vector(cnt'range)  := (others => '0');
	signal div_c, div_n: std_ulogic_vector(D downto 0) := (others => '0');
	signal pul_c, pul_n: std_ulogic := '0';
	signal pulse: std_ulogic := '0';
begin
	pulse  <= (not cr) and pul_n and (pul_c xor pul_n) after g.delay; -- rising edge detector
	baud   <= (not cr) and div_n(div_n'high) and (div_c(div_c'high) xor div_n(div_n'high)) after g.delay;
	sample <= pulse;

	process (clk, rst)
	begin
		if rst = '1' and g.asynchronous_reset then
			cmp_c <= cmp_init after g.delay;
			cnt_c <= (others => '0') after g.delay;
			div_c <= (others => '0') after g.delay;
			pul_c <= '0' after g.delay;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				cmp_c <= cmp_init after g.delay;
				cnt_c <= (others => '0') after g.delay;
				div_c <= (others => '0') after g.delay;
				pul_c <= '0' after g.delay;
			else
				cmp_c <= cmp_n after g.delay;
				cnt_c <= cnt_n after g.delay;
				div_c <= div_n after g.delay;
				pul_c <= pul_n after g.delay;
			end if;
		end if;
	end process;

	process (pulse, div_c, cr, we)
	begin
		div_n <= div_c after g.delay;
		if cr = '1' or we = '1' then
			div_n <= (others => '0') after g.delay;
			div_n(div_n'high) <= '1' after g.delay;
		elsif pulse = '1' then
			div_n <= std_ulogic_vector(unsigned(div_c) + 1) after g.delay;
		end if;
	end process;

	process (cmp_c, cnt_c, we, cnt, cr)
	begin
		cmp_n <= cmp_c after g.delay;
		cnt_n <= cnt_c after g.delay;

		if we = '1' then
			cmp_n <= cnt after g.delay;
			cnt_n <= (others => '0') after g.delay;
			pul_n <= '0' after g.delay;
		elsif cr = '1' then
			cnt_n <= (others => '0') after g.delay;
			pul_n <= '0' after g.delay;
		elsif cnt_c = cmp_c then
			cnt_n <= (others => '0') after g.delay;
			pul_n <= '1' after g.delay;
		else
			cnt_n <= std_ulogic_vector(unsigned(cnt_c) + 1) after g.delay;
			pul_n <= '0' after g.delay;
		end if;
	end process;
end architecture;

library ieee, work;
use ieee.std_logic_1164.all;
use work.uart_pkg.all;

entity uart_rx is
	generic (
		g:       uart_generics;
		N:       positive;
		D:       positive;
		format:  std_ulogic_vector(7 downto 0) := uart_8N1;
		use_cfg: boolean);
	port (
		clk:     in std_ulogic;
		rst:     in std_ulogic;
		cr:     out std_ulogic; -- reset sample/baud clock when start bit detected
		baud:    in std_ulogic;
		sample:  in std_ulogic; -- pulses at baud and sample rate
		failed: out std_ulogic_vector(1 downto 0);
		ctr:     in std_ulogic_vector(7 downto 0);
		ctr_we:  in std_ulogic;
		rx:      in std_ulogic; -- physical RX signal
		we:     out std_ulogic; -- write 'do' to output register
		do:     out std_ulogic_vector(N - 1 downto 0));
end entity;

architecture behaviour of uart_rx is
	type state is (reset, idle, start, data, parity, stop, done);
	signal state_c, state_n: state;
	signal ctr_c, ctr_n: std_ulogic_vector(ctr'range);
	signal rx_c, rx_n: std_ulogic_vector(do'range);
	signal sr_c, sr_n: std_ulogic_vector(D - 1 downto 0);
	signal rx_sync: std_ulogic;
	signal count_c, count_n: integer range 0 to N - 1;
	signal majority: std_ulogic;
	signal fail_c, fail_n: std_ulogic_vector(1 downto 0);
begin
	do     <= rx_c after g.delay;
	failed <= fail_c after g.delay;

	assert D < 4 severity failure;

	majority_1: if D = 1 generate
		majority <= sr_c(0) after g.delay;
	end generate;

	majority_2: if D = 2 generate
		majority <= sr_c(0) and sr_c(1) after g.delay; -- even wins is 'sr_c(0) or sr_c(1)'
	end generate;

	majority_3: if D = 3 generate
		majority <= (sr_c(0) and sr_c(1)) or (sr_c(1) and sr_c(2)) or (sr_c(0) and sr_c(2)) after g.delay;
	end generate;

	process (clk, rst)
		procedure reset is
		begin
			rx_c     <= (others => '0') after g.delay;
			sr_c     <= (others => '0') after g.delay;
			fail_c   <= (others => '0') after g.delay;
			state_c  <= reset after g.delay;
			count_c  <= 0 after g.delay;
			rx_sync  <= '0' after g.delay;
			if use_cfg then ctr_c  <= (others => '0') after g.delay; end if;
		end procedure;
	begin
		if rst = '1' and g.asynchronous_reset then
			reset;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				reset;
			else
				rx_c     <= rx_n after g.delay;
				sr_c     <= sr_n after g.delay;
				state_c  <= state_n after g.delay;
				count_c  <= count_n after g.delay;
				fail_c   <= fail_n after g.delay;
				rx_sync  <= rx after g.delay;
				if use_cfg then ctr_c <= ctr_n after g.delay; end if;
			end if;
		end if;
		if not use_cfg then ctr_c <= format after g.delay; end if;
	end process;

	process (rx_c, sr_c, ctr_c, ctr_we, ctr, state_c, rx_sync, baud, sample, count_c, fail_c, majority)
	begin
		fail_n  <= fail_c  after g.delay;
		rx_n    <= rx_c    after g.delay;
		sr_n    <= sr_c    after g.delay;
		state_n <= state_c after g.delay;
		we      <= '0'     after g.delay;
		cr      <= '0'     after g.delay;
		count_n <= count_c after g.delay;
		if use_cfg then ctr_n <= ctr_c   after g.delay; end if;

		if sample = '1' then
			sr_n <= sr_c(sr_c'high - 1 downto sr_c'low) & rx_sync after g.delay;
		end if;

		case state_c is
		when reset =>
			rx_n     <= (others => '0') after g.delay;
			sr_n     <= (others => '0') after g.delay;
			fail_n   <= (others => '0') after g.delay;
			if use_cfg then
				ctr_n    <= format after g.delay; -- 8 bits, 1 stop bit, parity off
			end if;
			state_n  <= idle after g.delay;
		when idle =>
			count_n <= 0 after g.delay;
			if rx_sync = '0' then -- and majority = '1' then
				state_n <= start after g.delay;
				cr      <= '1' after g.delay;
				sr_n    <= (others => '0') after g.delay;
				fail_n  <= (others => '0') after g.delay;
			end if;
		when start =>
			if baud = '1' then
				if majority /= '0' then
					state_n   <= done after g.delay; -- frame error
					fail_n(0) <= '1' after g.delay;
				else
					state_n <= data after g.delay;
				end if;
				sr_n <= (others => '0') after g.delay;
			end if;
		when data =>
			rx_n(count_c) <= majority after g.delay;
			if baud = '1' then
				if count_c = (ctr_data_bits(ctr_c) - 1) then
					count_n <= 0 after g.delay;
					if ctr_c(ctr_use_parity) = '1' then
						state_n <= parity after g.delay;
					else
						state_n <= stop after g.delay;
					end if;
				else
					count_n <= count_c + 1 after g.delay;
				end if;
				sr_n <= (others => '0') after g.delay;
			end if;
		when parity =>
			if baud = '1' then
				if (ctr_c(ctr_use_parity) = '1') and (majority /= parity(rx_c, ctr_c(ctr_even_parity))) then
					fail_n(1) <= '1' after g.delay; -- parity error, still process stop bits
				end if;
				state_n <= stop after g.delay;
				sr_n <= (others => '0') after g.delay;
			end if;
		when stop =>
			if baud = '1' then
				if majority /= '1' then
					state_n   <= done after g.delay; -- frame error
					fail_n(0) <= '1' after g.delay;
				elsif count_c = ctr_stop_bits(ctr_c) then
					state_n <= done after g.delay;
				else
					count_n <= count_c + 1 after g.delay;
				end if;
			end if;
		when done => -- The consuming module needs to store rx_c/fail_c immediately
			we      <= '1' after g.delay;
			state_n <= idle after g.delay;
		end case;

		if ctr_we = '1' then
			if not (state_c = idle or state_c = done or state_c = reset) then
				rx_n      <= (others => '0') after g.delay;
				state_n   <= idle after g.delay;
				we        <= '1' after g.delay;
				fail_n(0) <= '1' after g.delay; -- frame error!
			end if;
			ctr_n <= ctr after g.delay;
		end if;
	end process;
end architecture;

library ieee, work;
use ieee.std_logic_1164.all;
use work.uart_pkg.all;

entity uart_tx is
	generic (
		g:       uart_generics;
		N:       positive;
		format:  std_ulogic_vector(7 downto 0) := uart_8N1;
		use_cfg: boolean);
	port (
		clk:    in std_ulogic;
		rst:    in std_ulogic;
		cr:    out std_ulogic;
		baud:   in std_ulogic; -- Pulse at baud
		tx:    out std_ulogic;
		ok:    out std_ulogic;
		ctr:    in std_ulogic_vector(format'range);
		ctr_we: in std_ulogic;
		we:     in std_ulogic; -- di write enable
		di:     in std_ulogic_vector(N - 1 downto 0));
end entity;

architecture behaviour of uart_tx is
	type state is (reset, idle, start, data, parity, stop);
	signal state_c, state_n: state;
	signal di_c, di_n: std_ulogic_vector(di'range);
	signal ctr_c, ctr_n: std_ulogic_vector(ctr'range);
	signal busy: std_ulogic;
	signal parity_c, parity_n: std_ulogic;
	signal count_c, count_n: integer range 0 to 15;
begin
	busy <= '0' when state_c = idle else '1' after g.delay;
	ok <= not busy after g.delay;

	process (clk, rst)
		procedure reset is
		begin
			di_c     <= (others => '0') after g.delay;
			state_c  <= reset after g.delay;
			parity_c <= '0' after g.delay;
			count_c  <= 0 after g.delay;
			if use_cfg then ctr_c <= (others => '0') after g.delay; end if;
		end procedure;
	begin
		if rst = '1' and g.asynchronous_reset then
			reset;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				reset;
			else
				di_c     <= di_n     after g.delay;
				state_c  <= state_n  after g.delay;
				parity_c <= parity_n after g.delay;
				count_c  <= count_n  after g.delay;
				if use_cfg then ctr_c <= ctr_n after g.delay; end if;
			end if;
		end if;
		if not use_cfg then ctr_c <= format after g.delay; end if;
	end process;

	process (di_c, di, ctr_c, ctr_we, ctr, state_c, we, baud, parity_c, count_c)
	begin
		count_n <= count_c after g.delay;
		state_n <= state_c after g.delay;
		di_n    <= di_c after g.delay;
		if use_cfg then ctr_n <= ctr_c after g.delay; end if;
		tx <= '1' after g.delay;
		cr <= '0';

		if ctr_c(ctr_use_parity) = '1' then
			parity_n <= parity(di_c, ctr_c(ctr_even_parity)) after g.delay;
		else
			parity_n <= '0' after g.delay;
		end if;

		case state_c is
		when reset  =>
			state_n  <= idle after g.delay;
			ctr_n    <= format after g.delay; -- 8 bits, 1 stop bit, parity off
			count_n  <= 0 after g.delay;
			parity_n <= '0' after g.delay;
			di_n     <= (others => '0') after g.delay;
		when idle   =>
			count_n  <= 0 after g.delay;
			if use_cfg and ctr_we = '1' then -- NB. We can either lose data, or control writes
				ctr_n <= ctr after g.delay;
			elsif we = '1' then
				di_n    <= di after g.delay;
				cr      <= '1';
				state_n <= start after g.delay;
			end if;
		when start  =>
			tx <= '0' after g.delay;
			if baud = '1' then
				state_n <= data after g.delay;
			end if;
		when data   =>
			tx <= di_c(count_c) after g.delay;
			if baud = '1' then
				if count_c = (ctr_data_bits(ctr_c) - 1) then
					count_n <= 0 after g.delay;
					if ctr_c(ctr_use_parity) = '1' then
						state_n <= parity after g.delay;
					else
						state_n <= stop after g.delay;
					end if;
				else
					count_n <= count_c + 1 after g.delay;
				end if;
			end if;
		when parity =>
			tx <= parity_c after g.delay;
			if baud = '1' then
				state_n <= stop after g.delay;
			end if;
		when stop   =>
			tx <= '1' after g.delay;
			if baud = '1' then
				if count_c = ctr_stop_bits(ctr_c) then
					count_n <= 0 after g.delay;
					state_n <= idle after g.delay;
				else
					count_n <= count_c + 1 after g.delay;
				end if;
			end if;
		end case;
	end process;
end architecture;

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.uart_pkg.all;

entity uart_tb is
	generic(g: uart_generics);
end entity;

architecture testing of uart_tb is
	constant clock_period: time     := 1000 ms / g.clock_frequency;
	constant fifo_depth: natural    := 8;
	signal rst, clk:     std_ulogic := '1';
	signal stop:         boolean    := false;
	signal loopback:     boolean    := true;
	signal tx, rx:       std_ulogic;
	signal di, do:       std_ulogic_vector(7 downto 0);
	signal reg:          std_ulogic_vector(15 downto 0);
	signal clock_reg_tx_we: std_ulogic;
	signal clock_reg_rx_we: std_ulogic;
	signal control_reg_we:  std_ulogic;

	signal tx_fifo_full:  std_ulogic;
	signal tx_fifo_empty: std_ulogic;
	signal tx_fifo_we:    std_ulogic := '0';
	signal rx_fifo_full:  std_ulogic;
	signal rx_fifo_empty: std_ulogic;
	signal rx_fifo_re:    std_ulogic := '0';
begin
	-- duration: process begin wait for 20000 us; stop <= true; wait; end process;
	clk_process: process
	begin
		rst <= '1';
		wait for clock_period * 5;
		rst <= '0';
		while not stop loop
			clk <= '1';
			wait for clock_period / 2;
			clk <= '0';
			wait for clock_period / 2;
		end loop;
		wait;
	end process;

	stimulus: process
		procedure write(data: std_ulogic_vector(di'range)) is
		begin
			wait for clock_period * 1;
			while tx_fifo_full = '1' loop
				wait for clock_period;
			end loop;
			di <= data;
			tx_fifo_we <= '1';
			wait for clock_period;
			tx_fifo_we <= '0';
		end procedure;
	begin
		di <= x"00";
		wait until rst = '0';
		wait for clock_period;
		reg             <=  x"8080";
		control_reg_we  <=  '1';
		wait for clock_period;
		control_reg_we  <=  '0';
		reg             <=  x"0036";
		clock_reg_tx_we <=  '1';
		wait for clock_period;
		clock_reg_tx_we <=  '0';
		clock_reg_rx_we <=  '1';
		reg             <=  x"0035";
		wait for clock_period;
		clock_reg_rx_we <=  '0';
		wait for clock_period;

		write(x"AA");
		write(x"BB");
		write(x"CC");
		write(x"DD");
		write(x"EE");
		write(x"FF");
		wait for clock_period;
		while tx_fifo_empty = '0' loop
			wait for clock_period;
		end loop;
		loopback <= false;
		wait for clock_period * 50000;
		stop <= true;
		wait;
	end process;

	ack: process
	begin
		while not stop loop
			if rx_fifo_empty = '0' then
				rx_fifo_re <= '1';
			else
				rx_fifo_re <= '0';
			end if;
			wait for clock_period;
		end loop;
		wait;
	end process;
	rx <= tx when loopback else '0'; -- loop back test
	uut: work.uart_pkg.uart_top
		generic map (
		clock_frequency    => g.clock_frequency,
		delay              => g.delay,
		asynchronous_reset => g.asynchronous_reset,
		baud               => 115200,
		format             => uart_8N1,
		fifo_depth         => fifo_depth)
		port map (
			clk => clk,
			rst => rst,

			tx             =>  tx,
			tx_fifo_full   =>  tx_fifo_full,
			tx_fifo_empty  =>  tx_fifo_empty,
			tx_fifo_we     =>  tx_fifo_we,
			tx_fifo_data   =>  di,

			rx             =>  rx,
			rx_fifo_full   =>  rx_fifo_full,
			rx_fifo_empty  =>  rx_fifo_empty,
			rx_fifo_re     =>  rx_fifo_re,
			rx_fifo_data   =>  do,

			reg             => reg,
			clock_reg_tx_we => clock_reg_tx_we,
			clock_reg_rx_we => clock_reg_rx_we,
			control_reg_we  => control_reg_we);

end architecture;

