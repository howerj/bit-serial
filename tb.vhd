-- File:        tb.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- Email:       howe.r.j.89@gmail.com
-- License:     MIT
-- Description: Test bench for top level entity

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.all;
use std.textio.all;
use work.uart_pkg.all;

entity tb is
end tb;

architecture testing of tb is
	constant g: common_generics           := default_settings;
	constant clock_period:       time     := 1000 ms / g.clock_frequency;
	constant baud:               positive := 115200;
	constant configuration_file_name: string := "tb.cfg";
	constant N:                  positive := 16;

	signal stop:   boolean    := false;
	signal clk:    std_ulogic := '0';
	signal halt:   std_ulogic := '0';
	signal rst:    std_ulogic := '1';

	signal saw_char: boolean := false;

	signal ld: std_ulogic_vector(7 downto 0) := (others => '0');
	signal sw: std_ulogic_vector(7 downto 0) := x"AA";

	-- UART
	signal tx:             std_ulogic := '0';
	signal tx_fifo_full:   std_ulogic := '0';
	signal tx_fifo_empty:  std_ulogic := '0';
	signal tx_fifo_we:     std_ulogic := '0';
	signal tx_fifo_data:   std_ulogic_vector(7 downto 0) := (others => '0');
	signal rx:             std_ulogic := '0'; 
	signal rx_fifo_full:   std_ulogic := '0'; 
	signal rx_fifo_empty:  std_ulogic := '0'; 
	signal rx_fifo_re:     std_ulogic := '0';
	signal rx_fifo_data:   std_ulogic_vector(7 downto 0) := (others => '0');

	-- Test bench configurable options --

	type configurable_items is record
		clocks:         natural;
		forever:        boolean;
		debug:          natural;
		interactive:    natural;
		input_wait_for: time;
		report_uart:    boolean;
		report_number:  natural;
		input_single_line: boolean;
		uart_char_delay: time;
	end record;

	function set_configuration_items(ci: configuration_items) return configurable_items is
		variable r: configurable_items;
	begin
		r.clocks         := ci(0).value;
		r.forever        := ci(1).value > 0;
		r.debug          := ci(2).value;
		r.interactive    := ci(3).value;
		r.input_wait_for := ci(4).value * 1 ms;
		r.report_uart    := ci(5).value > 0;
		r.report_number  := ci(6).value;
		r.input_single_line := ci(7).value > 0;
		r.uart_char_delay := ci(8).value * 1 ms;
		return r;
	end function;

	constant configuration_default: configuration_items(0 to 8) := (
		(name => "Clocks..", value => 1000),
		(name => "Forever.", value => 0),
		(name => "Debug...", value => 0), -- TODO: Doesn't work for setting generics
		(name => "Interact", value => 0),
		(name => "InWaitMs", value => 15),
		(name => "UartRep.", value => 0),
		(name => "LogFor..", value => 256),
		(name => "1Line...", value => 1),
		(name => "UChDelay", value => 6)
	);

	-- Test bench configurable options --



	shared variable cfg: configurable_items := set_configuration_items(configuration_default);
	signal configured: boolean := false;
begin
	-- A more advanced test bench would hook the `rx`/`tx`
	-- lines up to a UART which could be connected up to
	-- stdin/stdout, or more realistically we could look
	-- for a startup string from the CPU and halt the 
	-- simulation when it has been received, or send
	-- a command to halt the CPU which it has to process.
	uut: entity work.top
		generic map(
			g          => g,
			file_name  => "bit.hex",
			N          => N,
			baud       => baud,
			debug      => cfg.debug)
		port map (
			clk  => clk,
--			rst  => rst,
			halt => halt,
			ld   => ld,
			sw   => sw,
			tx   => tx,
			rx   => rx);


	uart_0_blk: block
		signal uart_clock_rx_we, uart_clock_tx_we, uart_control_we: std_ulogic := '0';
		signal uart_reg: std_ulogic_vector(15 downto 0);
	begin
		uart_0: work.uart_pkg.uart_top
			generic map (
				baud => baud, 
				clock_frequency => g.clock_frequency, 
				delay => 0 ns, 
				asynchronous_reset => g.asynchronous_reset,
				use_cfg => false,
				fifo_depth => 4)
			port map (
				clk              =>  clk,
				rst              =>  rst,

				tx               =>  rx,
				tx_fifo_full     =>  tx_fifo_full,
				tx_fifo_empty    =>  tx_fifo_empty,
				tx_fifo_we       =>  tx_fifo_we,
				tx_fifo_data     =>  tx_fifo_data,

				rx               =>  tx,
				rx_fifo_full     =>  rx_fifo_full,
				rx_fifo_empty    =>  rx_fifo_empty,
				rx_fifo_re       =>  rx_fifo_re,
				rx_fifo_data     =>  rx_fifo_data,

				reg              =>  uart_reg,
				clock_reg_tx_we  =>  uart_clock_tx_we,
				clock_reg_rx_we  =>  uart_clock_rx_we,
				control_reg_we   =>  uart_control_we
			);
	end block;

	clock_process: process
		variable count: integer := 0;
		variable aline: line;
	begin
		stop <= false;
		wait until configured;
		wait for clock_period;
		-- N.B. We could add clock jitter if we wanted, however we would
		-- probably also want to add it to each of the modules clocks, along
		-- with an adjustable delay.
		while (count < cfg.clocks or cfg.forever)  and halt = '0' loop
			clk <= '1';
			wait for clock_period / 2;
			clk <= '0';
			wait for clock_period / 2;
			count := count + 1;
		end loop;
		if halt = '1' then
			write(aline, string'("{HALT}"));
		else
			write(aline, string'("{CYCLES}"));
		end if;

		if cfg.debug > 0 then
			writeline(OUTPUT, aline);
		end if;

		stop <= true;
		report "Clock process end";
		wait;
	end process;

	stimulus_process: process
		variable configuration_values: configuration_items(configuration_default'range) := configuration_default;
	begin
		-- write_configuration_tb(configuration_file_name, configuration_default);
		read_configuration_tb(configuration_file_name, configuration_values);
		cfg := set_configuration_items(configuration_values);
		configured <= true;

		rst <= '1';
		wait for clock_period;
		rst <= '0';

		configured <= true;
		while not stop loop
			if rx_fifo_empty = '0' then saw_char <= true; end if;
			wait for clock_period;
		end loop;
		if saw_char then
			report "Saw character via UART";
		else
			report "No output from unit" severity warning;
		end if;
		report "Stimulus Process end";
		wait;
	end process;

	output_process: process
		variable oline: line;
		variable c: character;
		variable have_char: boolean := true;
	begin
		wait until configured;

		if cfg.interactive < 1 then
			report "Output process turned off (`interactive < 1`)";
			wait;
		end if;

		report "Writing to STDOUT";
		while not stop loop
			wait until (rx_fifo_empty = '0' or stop);
			if not stop then
				wait for clock_period;
				rx_fifo_re <= '1';
				wait for clock_period;
				rx_fifo_re <= '0';
				c := character'val(to_integer(unsigned(rx_fifo_data)));
				if (cfg.report_uart) then
					report "BCPU -> UART CHAR: " & integer'image(to_integer(unsigned(rx_fifo_data))) & " CH: " & c;
				end if;
				write(oline, c);
				have_char := true;
				if rx_fifo_data = x"0d" then
					writeline(output, oline);
					have_char := false;
				end if;
			end if;
		end loop;
		if have_char then
			writeline(output, oline);
		end if;
		report "Output process end";
		wait;
	end process;

	-- The Input and Output mechanism that allows the tester to
	-- interact with the running simulation needs more work, it is buggy
	-- and experimental, but demonstrates the principle - that a VHDL
	-- test bench can be interacted with at run time.
	input_process: process
		variable c: character := ' ';
		variable iline: line;
		variable good: boolean := true;
		variable eoi:  boolean := false;
	begin
		tx_fifo_we <= '0';
		tx_fifo_data <= x"00";
		wait until configured;

		if cfg.interactive < 2 then
			report "Input process turned off (`interactive < 2`)";
			wait;
		end if;

		report "Waiting for " & time'image(cfg.input_wait_for) & " (before reading from STDIN)";
		wait for cfg.input_wait_for;
		report "Reading from STDIN (Hit EOF/CTRL-D/CTRL-Z After entering a line)";
		while stop = false and eoi = false loop
			if endfile(input) = true then exit; end if;
			report "INPUT-LINE> ";
			readline(input, iline);
			good := true;
			while good and not stop loop
				read(iline, c, good);
				if good then
					report "UART -> BCPU CHAR: " & integer'image(character'pos(c)) & " CH: " & c;
				else
					eoi := true;

					report "UART -> BCPU EOL/EOI: CR";
					c := CR;
					tx_fifo_data <= std_ulogic_vector(to_unsigned(character'pos(c), tx_fifo_data'length));
					tx_fifo_we <= '1';
					wait for clock_period;
					tx_fifo_we <= '0';
					wait for cfg.uart_char_delay;
					if stop then exit; end if;
					report "UART -> BCPU EOL/EOI: LF";
					c := LF;
				end if;
				tx_fifo_data <= std_ulogic_vector(to_unsigned(character'pos(c), tx_fifo_data'length));
				tx_fifo_we <= '1';
				wait for clock_period;
				tx_fifo_we <= '0';
				wait for cfg.uart_char_delay;
			end loop;
			if cfg.input_single_line then exit; end if;
		end loop;
		report "Input process end";
		wait;
	end process;

end architecture;


