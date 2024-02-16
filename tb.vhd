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

entity tb is
end tb;

architecture testing of tb is
	constant g: common_generics           := default_settings;
	constant clock_period:       time     := 1000 ms / g.clock_frequency;
	constant baud:               positive := 115200 * 10; -- speed up TX/RX for simulation
	shared variable clocks:      integer  := 10000;
	shared variable forever:     integer  := 0;
	shared variable debug:       integer  := 1;
	constant N:                  positive := 16;

	signal ld: std_ulogic_vector(7 downto 0) := (others => '0');
	signal sw: std_ulogic_vector(7 downto 0) := x"AA";
	signal stop:   boolean    := false;
	signal clk:    std_ulogic := '0';
	signal halt:   std_ulogic := '0';
	signal rst:    std_ulogic := '1';
	signal tx, rx: std_ulogic := '0';

	impure function configure(the_file_name: in string) return boolean is
		file     in_file: text is in the_file_name;
		variable in_line: line;
		variable i:       integer;
	begin
		if endfile(in_file) then return false; end if;
		readline(in_file, in_line); read(in_line, i);
		clocks := i;
		readline(in_file, in_line); read(in_line, i);
		forever := i;
		readline(in_file, in_line); read(in_line, i);
		debug := i;
		return true;
	end function;

	signal configured: boolean := configure("tb.conf");
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
			debug      => debug)
		port map (
			clk  => clk,
--			rst  => rst,
			halt => halt,
			ld   => ld,
			sw   => sw,
			tx   => tx,
			rx   => rx);

	clock_process: process
		variable count: integer := 0;
		variable aline: line;
	begin
		rst  <= '1';
		stop <= false;
		wait for clock_period;
		rst  <= '0';
		while (count < clocks or forever /= 0)  and halt = '0' loop
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

		if debug > 0 then
			writeline(OUTPUT, aline);
		end if;

		stop <= true;
		wait;
	end process;

	stimulus_process: process
	begin
		while stop = false loop
			wait for clock_period;
		end loop;
		wait;
	end process;
end architecture;

