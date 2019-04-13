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
		clk:         in std_ulogic;
		rst:         in std_ulogic;
		i:           in std_ulogic;
		o, a:       out std_ulogic;
   		oe, ie, ae: out std_ulogic;
		stop:       out std_ulogic);
end;

architecture rtl of bcpu is
	type state_t is (RESET, FETCH, EXECUTE, STORE, LOAD, ADVANCE, HALT);
	signal state_c, state_n: state_t := RESET;
	signal next_c,  next_n:  state_t := RESET;
	signal first_c, first_n: boolean := true;
	signal carry_c, carry_n: std_ulogic := '0';
	signal zero_c,  zero_n:  std_ulogic := '1';
	signal sig_c,   sig_n:   std_ulogic := '0';
	signal done_c,  done_n:  std_ulogic := '0';
	signal dline_c, dline_n: std_ulogic_vector(N + 1 downto 0) := (others => '0');
	signal acc_c,   acc_n:   std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal pc_c,    pc_n:    std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal op_c,    op_n:    std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal instruction:      std_ulogic_vector(3 downto 0)     := (others => '0');

	procedure adder (signal x, y, cin: in std_ulogic; signal sum, cout: out std_ulogic) is
	begin
		sum  <= x xor y xor cin;
		cout <= (x and y) or (cin and (x xor y));
	end procedure;
begin
	assert N >= 8 severity failure;
	instruction <= op_c(op_c'high downto op_c'high - 3);

	process (clk, rst)
	begin
		if rst = '1' and asynchronous_reset then
			state_c <= RESET;
			next_c  <= RESET;
			first_c <= true;
			dline_c <= (others => '0'); -- NB. Parallel reset
			acc_c   <= acc_n;
			pc_c    <= pc_n;
			op_c    <= op_n;
			sig_c   <= '0';
			carry_c <= '0';
			done_c  <= '0';
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				state_c <= RESET;
				next_c  <= RESET;
				first_c <= true;
				sig_c   <= '0';
				carry_c <= '0';
				done_c  <= '0';
				dline_c <= (others => '0'); -- NB. Parallel reset
				acc_c   <= acc_n;
				pc_c    <= pc_n;
				op_c    <= op_n;
			else
				state_c <= state_n;
				next_c  <= next_n;
				dline_c <= dline_n;
				first_c <= first_n;
				carry_c <= carry_n;
				zero_c  <= zero_n;
				acc_c   <= acc_n;
				pc_c    <= pc_n;
				op_c    <= op_n;
				sig_c   <= sig_n;
				done_c  <= done_n;
			end if;
		end if;
	end process;

	process (i, state_c, next_c, done_c, first_c, dline_c, acc_c, pc_c, op_c, carry_c, zero_c, sig_c, instruction)
	begin
		o  <= '0';
		a  <= '0';
		ie <= '0';
		ae <= '0';
		oe <= '0';
		stop    <= '0';
		dline_n <= dline_c(dline_c'high - 1 downto 0) & "0";
		state_n <= state_c;
		next_n  <= next_c;
		first_n <= first_c;
		acc_n   <= acc_c;
		pc_n    <= pc_c;
		op_n    <= op_c;
		carry_n <= carry_c;
		zero_n  <= zero_c;
		sig_n   <= sig_c;
		done_n  <= done_c;
		case state_c is
		when RESET   =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
			elsif dline_c(dline_c'high) = '1' then
				state_n <= FETCH;
				first_n <= true;
			else
				oe      <= '1';
				ae      <= '1';
				carry_n <= '0';
				zero_n  <= '1';
				sig_n   <= '0';
				acc_n   <= acc_c(acc_c'high - 1 downto 0) & "0";
				pc_n    <= pc_c(pc_c'high - 1 downto 0) & "0";
				op_n    <= op_c(op_c'high - 1 downto 0) & "0";
			end if;
		when FETCH   =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
			elsif dline_c(dline_c'high) = '1' then
				state_n <= EXECUTE;
				first_n <= true;
			else
				ie      <= '1';
				carry_n <= '0';
				op_n    <= op_c(op_c'high - 1 downto 0) & i;
			end if;
		when EXECUTE =>
			if dline_c(dline_c'high - 4) = '1' then
				done_n <= '1';
			end if;

			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
				next_n     <= ADVANCE;
				done_n     <= '0';
			elsif dline_c(dline_c'high) = '1' then
				state_n <= next_c;
				first_n <= true;
				carry_n <= '0';
			elsif done_c = '0' then
				   if instruction = x"0" then -- nop
				elsif instruction = x"1" then -- halt
					next_n <= HALT;
				elsif instruction = x"2" then -- jump
					a      <= pc_c(0);
					pc_n   <= pc_c(pc_c'high - 1 downto 0) & pc_c(pc_c'high);
					ae     <= '1';
					next_n <= FETCH;
				elsif instruction = x"3" then -- jumpz
					if zero_c = '1' then
						a      <= pc_c(0);
						pc_n   <= pc_c(pc_c'high - 1 downto 0) & pc_c(pc_c'high);
						ae     <= '1';
						next_n <= FETCH;
					end if;
				elsif instruction = x"4" then -- and
				elsif instruction = x"5" then -- or
				elsif instruction = x"6" then -- xor
				elsif instruction = x"7" then -- invert
				elsif instruction = x"8" then -- load
				elsif instruction = x"9" then -- store
				elsif instruction = x"A" then -- literal
				elsif instruction = x"B" then -- N/A
				elsif instruction = x"C" then -- add
				elsif instruction = x"D" then -- less
				elsif instruction = x"E" then -- N/A
				elsif instruction = x"F" then -- N/A
				end if;
			end if;
		when STORE   =>
		when LOAD    =>
		when ADVANCE =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
				sig_n      <= '0';
			elsif dline_c(dline_c'high) = '1' then
				state_n <= FETCH;
				first_n <= true;
			else
				adder(pc_c(0), dline_c(0), carry_c, sig_n, carry_n);
				pc_n <= sig_c & pc_c(pc_c'high downto 1);
				a    <= pc_c(0); -- a <= pc_n(0)
				ae   <= '1';
			end if;
		when HALT    => stop <= '1';
		end case;
	end process;
end architecture;
