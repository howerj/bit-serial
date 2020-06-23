-- File:        tb.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- License:     MIT
-- Description: Test bench for top level entity, this
-- test bench just exercises the bit-serial CPU with a
-- test program.

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.all;

entity tb is
end tb;

architecture testing of tb is
	constant g: common_generics           := default_settings;
	constant clock_period:       time     := 1000 ms / g.clock_frequency;
	constant clocks:             integer  := 20000;
	constant N:                  positive := 16;
	constant debug:              boolean  := true;

	signal ld: std_ulogic_vector(7 downto 0) := (others => '0');
	signal sw: std_ulogic_vector(7 downto 0) := x"AA";
	signal stop:   boolean    := false;
	signal clk:    std_ulogic := '0';
	signal halt:   std_ulogic := '0';
	signal rst:    std_ulogic := '1';
	signal tx, rx: std_ulogic := '0';
begin
	uut: entity work.top
		generic map(
			g          => g,
			file_name  => "bit.hex",
			N          => N,
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
	begin
		rst  <= '1';
		stop <= false;
		wait for clock_period;
		rst  <= '0';
		while count < clocks and halt = '0' loop
			clk <= '1';
			wait for clock_period / 2;
			clk <= '0';
			wait for clock_period / 2;
			count := count + 1;
		end loop;
		if halt = '1' then
			report "CPU IN HALT STATE";
		else
			report "SIMULATION CYCLES RAN OUT";
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
