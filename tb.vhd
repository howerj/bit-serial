library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

architecture testing of tb is
	constant clock_frequency: positive := 100_000_000;
	constant clock_period:    time     := 1000 ms / clock_frequency;
	constant clocks:          integer  := 1000;

	signal stop:  boolean    := false;
	signal clk:   std_ulogic := '0';
	signal rst:   std_ulogic := '1';
begin
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
end architecture;

