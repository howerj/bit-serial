-- Bit-serial CPU
library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bcpu is 
	generic (
		asynchronous_reset: boolean  := true; -- use asynchronous reset if true, synchronous if false
		delay:              time     := 0 ns; -- simulation only, gate delay
		N:                  positive := 16);
	port (
		clk:   in std_ulogic;
		rst:   in std_ulogic;
		
		i:          in std_ulogic;
		o, a:       out std_ulogic;
   		oe, ie, ae: out std_ulogic);
end;

architecture rtl of bcpu is
	type state_t is (
		RESET_0,   RESET_N, 
		ADDRESS_0, ADDRESS_N, 
		FETCH_0,   FETCH_N, 
		EXECUTE_0, EXECUTE_N, 
		PC_LOAD_0, PC_LOAD_N,
		PC_INC_0,  PC_INC_N,
		HALT);
	signal state: state_t := RESET_0;
	signal dline:       std_ulogic_vector(N     downto 0) := (others => '0');
	signal acc, pc, op: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal instruction: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal zero, negative: std_ulogic := '0';
begin
	assert N >= 8 severity failure;
	process (clk, rst)
	begin
		if rst = '1' and asynchronous_reset then
			state <= RESET_0;
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				state <= RESET_0;
			else
				null;
			end if;
		end if;
	end process;
end architecture;
