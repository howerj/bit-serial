-- File:        bit.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- License:     MIT
-- Description: An N-bit, simple and small bit serial CPU
--
-- TODO:
-- * Use <https://gaisler.com/doc/vhdl2proc.pdf> as an example
-- of how to structure this module; put everything in records.
-- * Add interrupt handling
-- * Add flags for instruction modes; such as rotate vs shift
-- * Try to merge ADVANCE into one of the other states if possible,
-- or at least do the PC+1 in parallel with EXECUTE.
-- * Try to share resource as much as possible, for example the
-- adder/subtractor, but only if that saves space.
-- * Add assertions, model/specify behaviour
-- * Each state has the same dline_c test, merge it

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
	type cmd_t is (
		iOR,   iAND,   iXOR,     iINVERT, 
		iADD,  iSUB,   iLSHIFT,  iRSHIFT,
		iLOAD, iSTORE, iLITERAL, iFLAGS, 
		iJUMP, iJUMPZ, i14,      i15
	);
	constant C:   integer := 0;
	constant U:   integer := 1;
	constant Z:   integer := 2;
	constant Ng:  integer := 3;
	constant HLT: integer := 4;
	constant R:   integer := 5;
	constant PCC: integer := 6; -- temp used by PC carry

	type bcpu_registers is record
		state: state_t;
		ns:    state_t;
		first: boolean;
		done:  std_ulogic;
		acc:   std_ulogic_vector(N - 1 downto 0);
		pc:    std_ulogic_vector(N - 1 downto 0);
		op:    std_ulogic_vector(N - 1 downto 0);
		flags: std_ulogic_vector(N - 1 downto 0);
		cmd:   std_ulogic_vector(3 downto 0);
	end record;

	signal state_c, state_n: state_t := RESET;
	signal next_c,  next_n:  state_t := RESET;
	signal first_c, first_n: boolean := true;
	signal done_c,  done_n:  std_ulogic := '0';
	signal dline_c, dline_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal acc_c,   acc_n:   std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal pc_c,    pc_n:    std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal op_c,    op_n:    std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal flags_c, flags_n: std_ulogic_vector(N - 1 downto 0) := (others => 'X');
	signal cmd_c,   cmd_n:   std_ulogic_vector(3 downto 0)     := (others => '0');
	signal cmd: cmd_t := iOR;

	procedure adder (x, y, cin: in std_ulogic; signal sum, cout: out std_ulogic) is
	begin
		sum  <= x xor y xor cin after delay;
		cout <= (x and y) or (cin and (x xor y)) after delay;
	end procedure;
begin
	assert N >= 8 severity failure;

	process (clk, rst)
		procedure reset is
		begin
			state_c <= RESET after delay;
			next_c  <= RESET after delay;
			first_c <= true  after delay;
			dline_c <= (others => '0') after delay; -- NB. Parallel reset
			acc_c   <= acc_n   after delay;
			pc_c    <= pc_n    after delay;
			op_c    <= op_n    after delay;
			cmd_c   <= cmd_n   after delay;
			flags_c <= flags_n after delay;
			done_c  <= '0' after delay;
		end procedure;
	begin
		if rst = '1' and asynchronous_reset then
			reset;
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				reset;
			else
				state_c <= state_n after delay;
				next_c  <= next_n  after delay;
				dline_c <= dline_n after delay;
				first_c <= first_n after delay;
				acc_c   <= acc_n   after delay;
				pc_c    <= pc_n    after delay;
				op_c    <= op_n    after delay;
				cmd_c   <= cmd_n   after delay;
				flags_c <= flags_n after delay;
				done_c  <= done_n  after delay;
			end if;
		end if;
	end process;

	cmd <= cmd_t'val(to_integer(unsigned(cmd_c)));
	process (i, state_c, next_c, done_c, first_c, dline_c, acc_c, pc_c, op_c, cmd_c, flags_c, cmd, acc_n, pc_n, flags_n)
	begin
		o       <= '0' after delay;
		a       <= '0' after delay;
		ie      <= '0' after delay;
		ae      <= '0' after delay;
		oe      <= '0' after delay;
		stop    <= '0' after delay;
		dline_n <= dline_c(dline_c'high - 1 downto 0) & "0" after delay;
		state_n <= state_c after delay;
		next_n  <= next_c  after delay;
		first_n <= first_c after delay;
		acc_n   <= acc_c   after delay;
		pc_n    <= pc_c    after delay;
		op_n    <= op_c    after delay;
		cmd_n   <= cmd_c   after delay;
		done_n  <= done_c  after delay;
		flags_n <= flags_c after delay;

		if dline_c(dline_c'high) = '1' then
			state_n <= next_c after delay;
			first_n <= true   after delay;
		end if;

		if dline_c(dline_c'high - 4) = '1' then
			done_n <= '1' after delay;
		end if;

		case state_c is
		when RESET   =>
			next_n <= FETCH after delay;
			if first_c then
				dline_n(0) <= '1' after delay;
				first_n    <= false after delay;
			else
				oe      <= '1' after delay;
				ae      <= '1' after delay;
				acc_n   <= "0" & acc_c(acc_c'high downto 1) after delay;
				pc_n    <= "0" & pc_c(pc_c'high downto 1) after delay;
				op_n    <= "0" & op_c(op_c'high downto 1) after delay;
				flags_n <= "0" & flags_c(flags_c'high downto 1) after delay;
			end if;

		when FETCH   =>
			if first_c then
				dline_n(0)  <= '1'   after delay;
				first_n     <= false after delay;
				flags_n(Z)  <= '1'   after delay;
				flags_n(Ng) <= acc_c(acc_c'high) after delay;
				done_n      <= '0' after delay;
			else
				ie          <= '1' after delay;

				acc_n <= acc_c(0) & acc_c(acc_c'high downto 1) after delay;
				if acc_c(0) = '1' then -- determine flag status before EXECUTE
					flags_n(Z) <= '0' after delay;
				end if;

				if done_c = '0' then
					op_n    <= i & op_c(op_c'high downto 1) after delay;
				else
					cmd_n   <= i   & cmd_c(cmd_c'high downto 1) after delay;
					op_n    <= "0" & op_c (op_c'high  downto 1) after delay;
				end if;
			end if;

			   if flags_c(HLT) = '1' then
				next_n <= HALT after delay;
			elsif flags_c(R) = '1' then
				next_n <= RESET after delay;
			else
				next_n <= EXECUTE after delay;
			end if;
		when EXECUTE =>
			next_n     <= ADVANCE after delay;
			if first_c then
				-- Carry and Borrow flags should be cleared manually.
				dline_n(0) <= '1'   after delay;
				first_n    <= false after delay;
				done_n     <= '0'   after delay;
			else
				case cmd is
				when iOR =>
					op_n  <= "0" & op_c (op_c'high  downto 1) after delay;
					acc_n <= (op_c(0) or acc_c(0)) & acc_c(acc_c'high downto 1) after delay;
				when iAND =>
					acc_n <= acc_c(0) & acc_c(acc_c'high downto 1) after delay;
					if done_c = '0' then
						op_n  <= "0" & op_c (op_c'high downto 1) after delay;
						acc_n <= (op_c(0) and acc_c(0)) & acc_c(acc_c'high downto 1) after delay;
					end if;
				when iXOR =>
					op_n  <= "0" & op_c (op_c'high downto 1) after delay;
					acc_n <= (op_c(0) xor acc_c(0)) & acc_c(acc_c'high downto 1) after delay;
				when iINVERT =>
					acc_n <= (not acc_c(0)) & acc_c(acc_c'high downto 1) after delay;

				when iADD =>
					acc_n <= "0" & acc_c(acc_c'high downto 1) after delay;
					op_n  <= "0" & op_c(op_c'high downto 1)   after delay;
					adder(acc_c(0), op_c(0), flags_c(C), acc_n(acc_n'high), flags_n(C));
				when iSUB =>
					acc_n <= "0" & acc_c(acc_c'high downto 1) after delay;
					op_n  <= "0" & op_c(op_c'high downto 1)   after delay;
					adder(acc_c(0), not op_c(0), flags_c(U), acc_n(acc_n'high), flags_n(U));
				when iLSHIFT =>
					if op_c(0) = '1' then
						acc_n  <= acc_c(acc_c'high - 1 downto 0) & "0" after delay;
					end if;
					op_n   <= "0" & op_c (op_c'high downto 1) after delay;
				when iRSHIFT =>
					if op_c(0) = '1' then
						acc_n  <= "0" & acc_c(acc_c'high downto 1) after delay;
					end if;
					op_n   <= "0" & op_c (op_c'high downto 1) after delay;

				when iLOAD => -- Could set a flag so we loaded/store via accumulator 
					ae     <=     '1' after delay;
					a      <= op_c(0) after delay;
					op_n   <= op_c(0) & op_c(op_c'high downto 1) after delay;
					next_n <= LOAD after delay;
				when iSTORE =>
					ae     <=     '1' after delay;
					a      <= op_c(0) after delay;
					op_n   <= op_c(0) & op_c(op_c'high downto 1) after delay;
					next_n <= STORE after delay;
				when iLITERAL =>
					acc_n  <= op_c(0) & acc_c(acc_c'high downto 1) after delay;
					op_n   <=     "0" & op_c (op_c'high downto 1)  after delay;
				when iFLAGS =>
					acc_n   <= flags_c(0) & acc_c(acc_c'high downto 1) after delay;
					flags_n <=    op_c(0) & flags_c(flags_c'high downto 1) after delay;
					op_n    <=        "0" & op_c(op_c'high downto 1) after delay;

				when iJUMP =>
					ae     <= '1' after delay;
					a      <= op_c(0) after delay;
					op_n   <= "0"     & op_c(op_c'high downto 1) after delay;
					pc_n   <= op_c(0) & pc_c(pc_c'high downto 1) after delay;
					next_n <= FETCH after delay;
				when iJUMPZ =>
					if flags_c(Z) = '1' then
						ae     <= '1' after delay;
						a      <= op_c(0) after delay;
						op_n   <= "0"     & op_c(op_c'high downto 1) after delay;
						pc_n   <= op_c(0) & pc_c(pc_c'high downto 1) after delay;
						next_n <= FETCH after delay;
					end if;
				when i14 => -- N/A
				when i15 => -- N/A
				end case;
			end if;

		when STORE   =>
			next_n <= ADVANCE after delay;
			if first_c then
				dline_n(0) <= '1'   after delay;
				first_n    <= false after delay;
			else
				o      <= acc_c(0) after delay;
				oe     <= '1' after delay;
				acc_n  <= acc_c(0) & acc_c(acc_c'high downto 1) after delay;
			end if;
		when LOAD    =>
			next_n <= ADVANCE after delay;
			if first_c then
				dline_n(0) <= '1'   after delay;
				first_n    <= false after delay;
			else
				ie    <= '1' after delay;
				acc_n <= i & acc_c(acc_c'high downto 1) after delay;
			end if;
		when ADVANCE =>
			next_n <= FETCH after delay;
			if first_c then
				dline_n(0)   <= '1'   after delay;
				first_n      <= false after delay;
				flags_n(PCC) <= '0'   after delay;
			else
				pc_n  <= "0" & pc_c(pc_c'high downto 1) after delay;
				adder(pc_c(0), dline_c(0), flags_c(PCC), pc_n(pc_n'high), flags_n(PCC));
				a    <= pc_n(pc_n'high) after delay; -- !
				ae   <= '1' after delay;
			end if;

		when HALT => stop <= '1' after delay;
		when others => next_n <= RESET;
		end case;
	end process;
end architecture;
