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

	-- TODO:
	-- * Use <https://gaisler.com/doc/vhdl2proc.pdf> as an example
	-- of how to structure this module; put everything in records.
	-- * Add delay estimates in
	-- * Add interrupt handling
	-- * Add flags for instruction modes; such as rotate vs shift
	-- * Try to merge ADVANCE into one of the other states if possible
	-- * Try to share resource as much as possible, for example the
	-- adder/subtractor, but only if that save space.
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
		sum  <= x xor y xor cin;
		cout <= (x and y) or (cin and (x xor y));
	end procedure;
begin
	assert N >= 8 severity failure;

	process (clk, rst)
		procedure reset is
		begin
			state_c <= RESET;
			next_c  <= RESET;
			first_c <= true;
			dline_c <= (others => '0'); -- NB. Parallel reset
			acc_c   <= acc_n;
			pc_c    <= pc_n;
			op_c    <= op_n;
			cmd_c   <= cmd_n;
			flags_c <= flags_n;
			done_c  <= '0';
		end procedure;
	begin
		if rst = '1' and asynchronous_reset then
			reset;
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				reset;
			else
				state_c <= state_n;
				next_c  <= next_n;
				dline_c <= dline_n;
				first_c <= first_n;
				acc_c   <= acc_n;
				pc_c    <= pc_n;
				op_c    <= op_n;
				cmd_c   <= cmd_n;
				flags_c <= flags_n;
				done_c  <= done_n;
			end if;
		end if;
	end process;

	cmd <= cmd_t'val(to_integer(unsigned(cmd_c)));
	process (i, state_c, next_c, done_c, first_c, dline_c, acc_c, pc_c, op_c, cmd_c, flags_c, cmd, acc_n, pc_n, flags_n)
	begin
		o       <= '0';
		a       <= '0';
		ie      <= '0';
		ae      <= '0';
		oe      <= '0';
		stop    <= '0';
		dline_n <= dline_c(dline_c'high - 1 downto 0) & "0";
		state_n <= state_c;
		next_n  <= next_c;
		first_n <= first_c;
		acc_n   <= acc_c;
		pc_n    <= pc_c;
		op_n    <= op_c;
		cmd_n   <= cmd_c;
		done_n  <= done_c;
		flags_n <= flags_c;
		case state_c is
		when RESET   =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
			else
				oe      <= '1';
				ae      <= '1';
				acc_n   <= "0" & acc_c(acc_c'high downto 1);
				pc_n    <= "0" & pc_c(pc_c'high downto 1);
				op_n    <= "0" & op_c(op_c'high downto 1);
				flags_n <= "0" & flags_c(flags_c'high downto 1);
			end if;

			if dline_c(dline_c'high) = '1' then
				state_n <= FETCH;
				first_n <= true;
			end if;
		when FETCH   =>
			if first_c then
				dline_n(0)  <= '1';
				first_n     <= false;
				flags_n(Z)  <= '1';
				flags_n(Ng) <= acc_c(acc_c'high);
				done_n      <= '0';
			else
				ie          <= '1';

				acc_n <= acc_c(0) & acc_c(acc_c'high downto 1);
				if acc_c(0) = '1' then -- determine flag status before EXECUTE
					flags_n(Z) <= '0';
				end if;

				if done_c = '0' then
					op_n    <= i & op_c(op_c'high downto 1);
				else
					cmd_n   <= i   & cmd_c(cmd_c'high downto 1);
					op_n    <= "0" & op_c (op_c'high  downto 1);
				end if;
			end if;

			if dline_c(dline_c'high - 4) = '1' then
				done_n <= '1';
			end if;

			if dline_c(dline_c'high) = '1' then
				   if flags_c(HLT) = '1' then
					state_n <= HALT;
				elsif flags_c(R) = '1' then
					state_n <= RESET;
				else
					state_n <= EXECUTE;
				end if;
				first_n <= true;
			end if;
		when EXECUTE =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
				next_n     <= ADVANCE;
				done_n     <= '0';
				if cmd = iSUB then -- Comparator!
					flags_n(U) <= '1'; -- may need to rethink this...
				end if;
				if cmd = iADD then
					flags_n(C) <= '0'; -- may need to rethink this...
				end if;
			else
				case cmd is
				when iOR =>
					op_n  <= "0" & op_c (op_c'high  downto 1);
					acc_n <= (op_c(0) or acc_c(0)) & acc_c(acc_c'high downto 1);
				when iAND =>
					if done_c = '0' then
						op_n  <= "0" & op_c (op_c'high downto 1);
						acc_n <= (op_c(0) and acc_c(0)) & acc_c(acc_c'high downto 1);
					else
						acc_n <= acc_c(0) & acc_c(acc_c'high downto 1);
					end if;
				when iXOR =>
					op_n  <= "0" & op_c (op_c'high downto 1);
					acc_n <= (op_c(0) xor acc_c(0)) & acc_c(acc_c'high downto 1);
				when iINVERT =>
					acc_n <= (not acc_c(0)) & acc_c(acc_c'high downto 1);

				when iADD =>
					acc_n <= "0" & acc_c(acc_c'high downto 1);
					op_n  <= "0" & op_c(op_c'high downto 1);
					adder(acc_c(0), op_c(0), flags_c(C), acc_n(acc_n'high), flags_n(C));
				when iSUB =>
					acc_n <= "0" & acc_c(acc_c'high downto 1);
					op_n  <= "0" & op_c(op_c'high downto 1);
					adder(acc_c(0), not op_c(0), flags_c(U), acc_n(acc_n'high), flags_n(U));
				when iLSHIFT =>
					if op_c(0) = '1' then
						acc_n  <= acc_c(acc_c'high - 1 downto 0) & "0";
					end if;
					op_n   <= "0" & op_c (op_c'high downto 1);
				when iRSHIFT =>
					if op_c(0) = '1' then
						acc_n  <= "0" & acc_c(acc_c'high downto 1);
					end if;
					op_n   <= "0" & op_c (op_c'high downto 1);

				when iLOAD =>
					a      <= acc_c(0);
					ae     <= '1';
					acc_n  <= acc_c(0) & acc_c(acc_c'high downto 1);
					next_n <= LOAD;
				when iSTORE =>
					a      <= acc_c(0);
					ae     <= '1';
					acc_n  <= acc_c(0) & acc_c(acc_c'high downto 1);
					next_n <= STORE;
				when iLITERAL =>
					acc_n  <= op_c(0) & acc_c(acc_c'high downto 1);
					op_n   <=     "0" & op_c (op_c'high downto 1);
				when iFLAGS =>
					acc_n   <= flags_c(0) & acc_c(acc_c'high downto 1);
					flags_n <=    op_c(0) & flags_c(flags_c'high downto 1);
					op_n    <=        "0" & op_c(op_c'high downto 1);

				when iJUMP =>
					ae     <= '1';
					a      <= op_c(0);
					op_n   <= "0"     & op_c(op_c'high downto 1);
					pc_n   <= op_c(0) & pc_c(pc_c'high downto 1);
					next_n <= FETCH;
				when iJUMPZ =>
					if flags_c(Z) = '1' then
						ae     <= '1';
						a      <= op_c(0);
						op_n   <= "0"     & op_c(op_c'high downto 1);
						pc_n   <= op_c(0) & pc_c(pc_c'high downto 1);
						next_n <= FETCH;
					end if;
				when i14 => -- N/A
				when i15 => -- N/A
				end case;
			end if;

			if dline_c(dline_c'high - 4) = '1' then
				done_n <= '1';
			end if;

			if dline_c(dline_c'high) = '1' then
				state_n <= next_c;
				first_n <= true;
			end if;
		when STORE   =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
			else
				o      <= acc_c(0);
				oe     <= '1';
				acc_n  <= acc_c(0) & acc_c(acc_c'high downto 1);
			end if;
			if dline_c(dline_c'high) = '1' then
				state_n <= ADVANCE;
				first_n <= true;
			end if;
		when LOAD    =>
			if first_c then
				dline_n(0) <= '1';
				first_n    <= false;
			else
				ie     <= '1';
				acc_n  <= i & acc_c(acc_c'high downto 1);
			end if;
			if dline_c(dline_c'high) = '1' then
				state_n <= ADVANCE;
				first_n <= true;
			end if;
		when ADVANCE =>
			if first_c then
				dline_n(0)   <= '1';
				first_n      <= false;
				flags_n(PCC) <= '0';
			else
				pc_n  <= "0" & pc_c(pc_c'high downto 1);
				adder(pc_c(0), dline_c(0), flags_c(PCC), pc_n(pc_n'high), flags_n(PCC));
				a    <= pc_c(0);
				ae   <= '1';
			end if;

			if dline_c(dline_c'high) = '1' then
				-- if PCC is true when done, we should HALT?
				state_n <= FETCH;
				first_n <= true;
			end if;
		when HALT    => stop <= '1';
		end case;
	end process;
end architecture;
