library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
	generic (
		asynchronous_reset: boolean  := true; -- use asynchronous reset if true, synchronous if false
		delay:              time     := 0 ns; -- simulation only, gate delay
		file_name:          string;
		N:                  positive);
	port (
		clk:         in std_ulogic;
		rst:         in std_ulogic;
		tx:         out std_ulogic;
		rx:          in std_ulogic);
end entity;

architecture rtl of top is
	constant W:   positive := N - 4;
	signal i:                std_ulogic := 'X';
	signal o, a, oe, ie, ae: std_ulogic := 'X';
	signal stop:             std_ulogic := 'X';
begin
	-- TODO: Add UART module in

	program: entity work.mem
		generic map(
			asynchronous_reset => asynchronous_reset,
			delay              => delay,
			file_name          => file_name,
			W                  => W,
			N                  => N)
		port map (
			clk => clk, rst => rst,
			i => o,
			o => i,
			a => a, oe => ie, ie => oe, ae => ae);

	cpu: entity work.bcpu 
		generic map (
			asynchronous_reset => asynchronous_reset,
			delay              => delay,
			N                  => N)
		port map (
			clk => clk, rst => rst,
			i => i, 
			o => o, a => a, oe => oe, ie => ie, ae => ae,
			stop => stop);
end architecture;
