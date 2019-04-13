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
				dline <= dline(N - 2 downto 0) & "0";
				pc    <= pc;
				op    <= op;
				state <= state;
				zero  <= zero;
				o     <= '0';
				a     <= '0';
				oe    <= '0';
				ie    <= '0';
				ae    <= '0';
				case state is
				when RESET_0 =>
					dline    <= (others => '0'); -- parallel!
					dline(0) <= '1';
					state    <= RESET_N;
				when RESET_N =>
					if dline(N) = '1' then
						state <= FETCH_0;
					else
						pc  <=  pc(N - 2 downto 0) & "0";
						acc <= acc(N - 2 downto 0) & "0";
						op  <=  op(N - 2 downto 0) & "0";
						instruction <= instruction(N - 2 downto 0) & "0";
					end if;
				when ADDRESS_0 =>
					dline(0) <= '1';
					state    <= ADDRESS_N;
					ae       <= '1';
					op       <= pc; -- parallel!
				when ADDRESS_N =>
					if dline(N) = '1' then
						state <= FETCH_0;
					else
						a  <= op(N - 1);
						op <= op(N - 2 downto 0) & "0";
					end if;
				when FETCH_0 =>
					dline(0) <= '1';
					state    <= FETCH_N;
					ie       <= '1';
				when FETCH_N =>
					if dline(N) = '1' then
						state <= EXECUTE_N;
					else
						instruction <= instruction(N - 2 downto 0) & i;
					end if;
				-- TODO: Increment Address Here
				when EXECUTE_0 =>
					dline(0) <= '1';
					state    <= EXECUTE_N;
					ie       <= '1';
				when EXECUTE_N =>
					case instruction(3 downto 0) is
					when x"0" => state <= HALT;
					when x"1" =>
						if instruction(4) = '1' then
							state <= PC_LOAD_0;
						end if;
						if instruction(5) = '1' and zero = '1' then
							state <= PC_LOAD_0;
						end if;
					when x"2" =>
					when x"3" =>
					when x"4" =>
					when x"5" =>
					when x"6" =>
					when x"7" =>
					when x"8" =>
					when x"9" =>
					when x"A" =>
					when others => 
					end case;
				when PC_INC_0  =>
				when PC_INC_N  =>
				when PC_LOAD_0 =>
				when PC_LOAD_N =>
				when HALT =>
				end case;
			end if;
		end if;
	end process;
end architecture;
