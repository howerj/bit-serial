library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

architecture testing of tb is
	constant clock_frequency:    positive := 100_000_000;
	constant clock_period:       time     := 1000 ms / clock_frequency;
	constant clocks:             integer  := 1000;
	constant N:                  positive := 16;
	constant delay:              time     := 0 ns;
	constant asynchronous_reset: boolean  := false;

	signal stop:  boolean    := false;
	signal clk:   std_ulogic := '0';
	signal rst:   std_ulogic := '1';
	signal i:                std_ulogic := 'X';
	signal o, a, oe, ie, ae: std_ulogic := 'X';
	signal halted:           std_ulogic := 'X';
begin
	sm: entity work.mem
		generic map(
			asynchronous_reset => asynchronous_reset,
			delay              => delay,
			N                  => N)
		port map (
			clk => clk, rst => rst,
			i => o,
			o => i,
			a => a, oe => ie, ie => oe, ae => ae);

	uut: entity work.bcpu 
		generic map (
			asynchronous_reset => asynchronous_reset,
			delay              => delay,
			N                  => N)
		port map (
			clk => clk, rst => rst,
			i => i,
			o => o, a => a, oe => oe, ie => ie, ae => ae,
			stop => halted);

	clock_process: process
		variable count: integer := 0;
	begin
		rst  <= '1';
		stop <= false;
		wait for clock_period;
		rst  <= '0';
		while count < clocks loop
			clk <= '1';
			wait for clock_period / 2;
			clk <= '0';
			wait for clock_period / 2;
			count := count + 1;
		end loop;
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

