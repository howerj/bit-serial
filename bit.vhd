-- File:        bit.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- License:     MIT
-- Description: An N-bit, simple and small bit serial CPU
--
-- TODO:
-- * Add interrupt handling, which will require a way of saving
-- the program counter somewhere.
-- * Add flags for instruction modes; such as rotate vs shift
-- * Try to merge ADVANCE into one of the other states if possible,
-- or at least do the PC+1 in parallel with EXECUTE.
-- * Try to share resource as much as possible, for example the
-- adder/subtractor, but only if that saves space.
-- * Add assertions, model/specify behaviour
--   - Assert only one bit set in dline, and one bit always set
--   when in certain states and not-first
--   - Assert state transitions
-- * Sort out subtraction flags; should probably have another flag
-- for the result and set initial borrow to '1'.

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
	constant Cy:   integer := 0; -- Carry; set by addition
	constant U:    integer := 1; -- Underflow/Borrow; set by subtraction 
	constant Z:    integer := 2; -- Accumulator is zero
	constant Ng:   integer := 3; -- Accumulator is negative
	constant HLT:  integer := 4; -- Halt CPU
	constant R:    integer := 5; -- Reset CPU
	constant ROT:  integer := 6; -- Use rotate instead of shift
	constant PCC:  integer := 7; -- temp used by PC carry
	constant DONE: integer := 8; -- done processing operand flag (processing last four bits)
	constant UT:   integer := 9; -- temporary underflow flag

	type bcpu_registers is record
		state:  state_t;    -- state machine register
		choice: state_t;    -- computed next state
		first:  boolean;    -- First flag (TODO: remove, use a flag)
		dline:  std_ulogic_vector(N - 1 downto 0); -- delay line, 16 cycles, our timer
		acc:    std_ulogic_vector(N - 1 downto 0); -- accumulator
		pc:     std_ulogic_vector(N - 1 downto 0); -- program counter
		op:     std_ulogic_vector(N - 1 downto 0); -- operand to instruction
		flags:  std_ulogic_vector(N - 1 downto 0); -- flags register
		cmd:    std_ulogic_vector(3 downto 0);     -- instruction
	end record;

	constant bcpu_default: bcpu_registers := (
		state  => RESET,
		choice => RESET,
		first  => true,
		dline  => (others => '0'),
		acc    => (others => 'X'),
		pc     => (others => 'X'),
		op     => (others => 'X'),
		flags  => (others => 'X'),
		cmd    => (others => 'X')
	);

	signal c, f: bcpu_registers := bcpu_default;
	signal cmd: cmd_t := iOR;
	signal add1, add2, acin, ares, acout: std_ulogic := '0';

	procedure adder (x, y, cin: in std_ulogic; signal sum, cout: out std_ulogic) is
	begin
		sum  <= x xor y xor cin after delay;
		cout <= (x and y) or (cin and (x xor y)) after delay;
	end procedure;
begin
	assert N >= 8 severity failure;
	adder (add1, add2, acin, ares, acout);         -- shared adder
	cmd <= cmd_t'val(to_integer(unsigned(c.cmd))); -- used for debug purposes

	process (clk, rst, f)
		procedure reset is
		begin
			c       <= bcpu_default after delay;
			c.acc   <= f.acc   after delay;
			c.pc    <= f.pc    after delay;
			c.op    <= f.op    after delay;
			c.flags <= f.flags after delay;
			c.cmd   <= f.cmd   after delay;
		end procedure;
	begin
		if rst = '1' and asynchronous_reset then
			reset;
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				reset;
			else
				c <= f after delay;
			end if;
		end if;
	end process;

	process (i, c, cmd, ares, acout)
	begin
		o    <= '0' after delay;
		a    <= '0' after delay;
		ie   <= '0' after delay;
		ae   <= '0' after delay;
		oe   <= '0' after delay;
		stop <= '0' after delay;
		add1 <= '0' after delay;
		add2 <= '0' after delay;
		acin <= '0' after delay;
		f       <= c;
		f.dline <= c.dline(c.dline'high - 1 downto 0) & "0" after delay;

		if c.dline(c.dline'high) = '1' then
			f.state <= c.choice after delay;
			f.first <= true     after delay;
		end if;

		if c.dline(c.dline'high - 4) = '1' then
			f.flags(DONE) <= '1' after delay;
		end if;

		case c.state is
		when RESET   =>
			f.choice <= FETCH;
			if c.first then
				f.dline(0)  <= '1'   after delay;
				f.first     <= false after delay;
			else
				ae      <= '1' after delay;
				oe      <= '1' after delay;
				f.acc   <= "0" & c.acc(c.acc'high downto 1) after delay;
				f.pc    <= "0" & c.pc (c.pc'high  downto 1) after delay;
				f.op    <= "0" & c.op (c.op'high  downto 1) after delay;
				f.flags <= "0" & c.flags(c.flags'high downto 1) after delay;
			end if;
		when FETCH   =>
			if c.first then
				f.dline(0)  <= '1'   after delay;
				f.first     <= false after delay;
				f.flags(Z)  <= '1'   after delay;
				f.flags(Ng) <= c.acc(c.acc'high) after delay;
				f.flags(DONE)      <= '0' after delay;
			else
				ie          <= '1' after delay;

				f.acc <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
				if c.acc(0) = '1' then -- determine flag status before EXECUTE
					f.flags(Z) <= '0' after delay;
				end if;

				if c.flags(DONE) = '0' then
					f.op    <= i & c.op(c.op'high downto 1) after delay;
				else
					f.cmd   <= i   & c.cmd(c.cmd'high downto 1) after delay;
					f.op    <= "0" & c.op (c.op'high  downto 1) after delay;
				end if;
			end if;

			   if c.flags(HLT) = '1' then
				f.choice <= HALT after delay;
			elsif c.flags(R) = '1' then
				f.choice <= RESET after delay;
			else
				f.choice <= EXECUTE after delay;
			end if;
		when EXECUTE =>
			f.choice     <= ADVANCE after delay;
			if c.first then
				-- Carry and Borrow flags should be cleared manually.
				f.dline(0)    <= '1'   after delay;
				f.first       <= false after delay;
				f.flags(DONE) <= '0'   after delay;
				f.flags(UT)   <= '1'   after delay; -- subtract one 
			else
				case cmd is -- ALU
				when iOR =>
					f.op  <= "0" & c.op (c.op'high  downto 1) after delay;
					f.acc <= (c.op(0) or c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
				when iAND =>
					f.acc <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
					if c.flags(DONE) = '0' then
						f.op  <= "0" & c.op (c.op'high downto 1) after delay;
						f.acc <= (c.op(0) and c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
					end if;
				when iXOR =>
					f.op  <= "0" & c.op (c.op'high downto 1) after delay;
					f.acc <= (c.op(0) xor c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
				when iINVERT =>
					f.acc <= (not c.acc(0)) & c.acc(c.acc'high downto 1) after delay;

				when iADD =>
					f.acc <= "0" & c.acc(c.acc'high downto 1) after delay;
					f.op  <= "0" & c.op(c.op'high downto 1)   after delay;
					add1  <=    c.acc(0) after delay;
					add2  <=     c.op(0) after delay;
					acin  <= c.flags(Cy) after delay;
					f.acc(f.acc'high) <= ares after delay;
					f.flags(Cy) <= acout after delay;
				when iSUB =>
					f.acc <= "0" & c.acc(c.acc'high downto 1) after delay;
					f.op  <= "0" & c.op(c.op'high downto 1)   after delay;
					add1  <=    c.acc(0) after delay;
					add2  <= not c.op(0) after delay;
					acin  <= c.flags(UT) after delay;
					f.acc(f.acc'high) <= ares after delay;
					f.flags(UT) <= acout after delay;
					f.flags(U)  <= acout after delay;
				when iLSHIFT =>
					if c.op(0) = '1' then
						f.acc  <= c.acc(c.acc'high - 1 downto 0) & "0" after delay;
						if c.flags(ROT) = '1' then
							f.acc  <= c.acc(c.acc'high - 1 downto 0) & c.acc(0) after delay;
						end if;
					end if;
					f.op   <= "0" & c.op (c.op'high downto 1) after delay;
				when iRSHIFT =>
					if c.op(0) = '1' then
						f.acc  <= "0" & c.acc(c.acc'high downto 1) after delay;
						if c.flags(ROT) = '1' then
							f.acc  <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
						end if;
					end if;
					f.op   <= "0" & c.op (c.op'high downto 1) after delay;

				when iLOAD => -- Could set a flag so we loaded/store via accumulator 
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					f.op   <= c.op(0) & c.op(c.op'high downto 1) after delay;
					f.choice <= LOAD after delay;
				when iSTORE =>
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					f.op   <= c.op(0) & c.op(c.op'high downto 1) after delay;
					f.choice <= STORE after delay;
				when iLITERAL =>
					f.acc  <= c.op(0) & c.acc(c.acc'high downto 1) after delay;
					f.op   <=     "0" & c.op (c.op'high downto 1)  after delay;
				when iFLAGS =>
					f.acc   <= c.flags(0) & c.acc(c.acc'high downto 1) after delay;
					f.flags <=    c.op(0) & c.flags(c.flags'high downto 1) after delay;
					f.op    <=        "0" & c.op(c.op'high downto 1) after delay;

				when iJUMP =>
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
					f.pc   <= c.op(0) & c.pc(c.pc'high downto 1) after delay;
					f.choice <= FETCH after delay;
				when iJUMPZ =>
					if c.flags(Z) = '1' then
						ae     <=     '1' after delay;
						a      <= c.op(0) after delay;
						f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
						f.pc   <= c.op(0) & c.pc(c.pc'high downto 1) after delay;
						f.choice <= FETCH after delay;
					end if;
				when i14 => -- N/A
				when i15 => -- N/A
				end case;
			end if;

		when STORE   =>
			f.choice <= ADVANCE after delay;
			if c.first then
				f.dline(0) <= '1'   after delay;
				f.first    <= false after delay;
			else
				o      <= c.acc(0) after delay;
				oe     <= '1'      after delay;
				f.acc  <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
			end if;
		when LOAD    =>
			f.choice <= ADVANCE after delay;
			if c.first then
				f.dline(0) <= '1'   after delay;
				f.first    <= false after delay;
			else
				ie    <= '1' after delay;
				f.acc <= i & c.acc(c.acc'high downto 1) after delay;
			end if;
		when ADVANCE =>
			f.choice <= FETCH after delay;
			if c.first then
				f.dline(0)   <= '1'   after delay;
				f.first      <= false after delay;
				f.flags(PCC) <= '0'   after delay;
			else
				f.pc <= "0" & c.pc(c.pc'high downto 1) after delay;
				add1 <=      c.pc(0) after delay;
				add2 <=   c.dline(0) after delay;
				acin <= c.flags(PCC) after delay;
				f.pc(f.pc'high) <= ares  after delay;
				a               <= ares  after delay;
				f.flags(PCC)    <= acout after delay;
				ae   <= '1' after delay;
			end if;
		when HALT => stop <= '1' after delay;
		when others => f.choice <= RESET;
		end case;
	end process;
end architecture;

