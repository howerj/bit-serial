-- File:        bit.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- Email:       howe.r.j.89@gmail.com
-- License:     MIT
-- Description: An N-bit, simple and small bit serial CPU

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- for debug only, not needed for synthesis

-- The bit-serial CPU itself, the interface is bit-serial as well as the
-- CPU, address and data are N bits wide. The enable lines are held
-- high for N cycles when data is clocked in or out, and a complete read or
-- write consists of N cycles (although those cycles may not be contiguous,
-- it is up to the BCPU). The three enable lines are mutually exclusive,
-- only one will be active at any time.
--
-- The CPU should come with a working Forth image that demonstrates
-- possibilities of the CPU, allowing the user to interactively program
-- it.
--
-- There are a few configurable items, but the defaults should work fine.
--
-- Bit serial CPUs are quite slow, nonetheless there are quite a few
-- optimizations that could be done to reduce the number of cycles needed
-- to execute certain instructions and perhaps even changes to CPU behavior
-- and instructions themselves. It should not be thought that this design
-- is optimal, it is quite small however.
--
-- One way to optimize this would be directly instantiate individual
-- LUTs, which would make the CPU FPGA family specific, see
-- <https://www.fpgarelated.com/showarticle/797.php> or "Inside the 
-- Spartan-6: Using LUTs to optimize circuits Victor Yurkovsky, June 24, 2015".
--
-- Other directions the CPU could be taken in are:
--
-- * Make the CPU more configurable. This could be done easily with
-- a `std_ulogic_vector` generic to turn on/off instructions (for example).
-- * Optionally process multiple bits at a time instead of just one
-- bit (configurable with a generic). We could process any number of
-- bits so long as it cleanly divided the CPU width.
-- * Try to add new functionality without increasing the CPU size,
-- such as a timer facility, or interrupts, or new instructions.
--
--
entity bcpu is
	generic (
		asynchronous_reset: boolean    := true;   -- use asynchronous reset if true, synchronous if false
		delay:              time       := 0 ns;   -- simulation only, gate delay
		N:                  positive   := 16;     -- size of the CPU, minimum is 8
		jumpz:              std_ulogic := '1';    -- jump on zero = '1', jump on non-zero = '0'
		debug:              natural    := 0);     -- debug level, 0 = off
	port (
		clk, rst:       in std_ulogic; -- clock line and synchronous/asynchronous reset
		i:              in std_ulogic; -- 'i' = input line
		o, a:          out std_ulogic; -- 'o' = output line, 'a' = address line
		oe, ie, ae: buffer std_ulogic; -- 'oe' = output enable, 'ie' = input enable, 'ae' = address enable
		stop:          out std_ulogic); -- CPU halted
end;

architecture rtl of bcpu is
	type state_t is (RESET, FETCH, INDIRECT, OPERAND, EXECUTE, STORE, LOAD, ADVANCE, HALT);
	type cmd_t is (
		iOR,     iAND,    iXOR,     iADD,
		iLSHIFT, iRSHIFT, iLOAD,    iSTORE,
		iLOADC,  iSTOREC, iLITERAL, iUNUSED,
		iJUMP,   iJUMPZ,  iSET,     iGET);

	-- A parity flag could be added if needed as it is
	-- easy to calculate. 
	constant Cy:  integer :=  0; -- Carry; set by addition
	constant Z:   integer :=  1; -- Accumulator is zero
	constant Ng:  integer :=  2; -- Accumulator is negative
	constant R:   integer :=  3; -- Reset CPU
	constant HLT: integer :=  4; -- Halt CPU

	type registers_t is record
		state:  state_t;    -- state machine register
		choice: state_t;    -- computed next state
		first:  boolean;    -- First flag, for setting up an instruction
		last4:  boolean;    -- Are we processing the last 4 bits of the instruction?
		indir:  boolean;    -- does the instruction require indirection of the operand?
		tcarry: std_ulogic; -- temporary carry flag
		dline:  std_ulogic_vector(N - 1 downto 0); -- delay line, 16 cycles, our timer
		acc:    std_ulogic_vector(N - 1 downto 0); -- accumulator
		pc:     std_ulogic_vector(N - 1 downto 0); -- program counter
		op:     std_ulogic_vector(N - 1 downto 0); -- operand to instruction
		flags:  std_ulogic_vector(N - 1 downto 0); -- flags register
		cmd:    std_ulogic_vector(3 downto 0);     -- instruction
	end record;

	constant registers_default: registers_t := (
		state  => RESET,
		choice => RESET,
		first  => true,
		last4  => false,
		indir  => false,
		tcarry => 'X',
		dline  => (others => '0'),
		acc    => (others => 'X'),
		pc     => (others => 'X'),
		op     => (others => 'X'),
		flags  => (others => 'X'),
		cmd    => (others => 'X'));

	signal c, f: registers_t := registers_default; -- BCPU registers, all of them.
	-- These signals are not used to hold state. The 'c' and 'f' registers
	-- do that.
	signal cmd: cmd_t; -- Shows up nicely in traces as an enumerated value
	signal add1, add2, acin, ares, acout: std_ulogic; -- shared adder signals
	signal last4, last:                   std_ulogic; -- state sequence signals

	-- 'adder' implements a full adder, which is all we need to implement
	-- N-bit addition in a bit serial architecture. It is used in the instruction
	-- "iADD" and to increment the program counter.
	procedure adder (x, y, cin: in std_ulogic; signal sum, cout: out std_ulogic) is
	begin
		sum  <= x xor y xor cin after delay;
		cout <= (x and y) or (cin and (x xor y)) after delay;
	end procedure;

	-- 'bit_count' is used for assertions and nothing else. It counts the
	-- number of bits in a 'std_ulogic_vector'.
	function bit_count(bc: in std_ulogic_vector) return natural is
		variable count: natural := 0;
	begin
		for index in bc'range loop
			if bc(index) = '1' then
				count := count + 1;
			end if;
		end loop;
		return count;
	end function;

	-- Obviously this does not synthesize, which is why synthesis is turned
	-- off for the body of this function, it does make debugging much easier
	-- though, we will be able to see which instructions are executed and do so
	-- by name.
	procedure print_debug_info is
		variable ll: line;

		function hx(slv: in std_ulogic_vector) return string is -- std_ulogic_vector to hex string
			constant cv: string := "0123456789ABCDEF";
			constant qu: integer := slv'length   / 4;
			constant rm: integer := slv'length mod 4;
			variable rs: string(1 to qu);
			variable sl: std_ulogic_vector(3 downto 0);
		begin
			assert rm = 0 severity failure;
			for l in 0 to qu - 1 loop
				sl := slv((l * 4) + 3 downto (l * 4));
				rs(qu - l) := cv(to_integer(unsigned(sl)) + 1);
			end loop;
			return rs;
		end function;

		function yn(sl: std_ulogic; ch: character) return string is -- print a flag
			variable rs: string(1 to 2) := "- ";
		begin
			if sl = '1' then
				rs(1) := ch;
			end if;
			return rs;
		end function;
	begin
		-- synthesis translate_off
		if debug > 0 then
			if c.state = EXECUTE and c.first then
				write(ll, hx(c.pc)    & ": ");
				write(ll, cmd_t'image(cmd)   & HT);
				write(ll, hx(c.acc)   & " ");
				write(ll, hx(c.op)    & " ");
				write(ll, hx(c.flags) & " ");
				write(ll, yn(c.flags(Cy),  'C'));
				write(ll, yn(c.flags(Z),   'Z'));
				write(ll, yn(c.flags(Ng),  'N'));
				write(ll, yn(c.flags(R),   'R'));
				write(ll, yn(c.flags(HLT), 'H'));
				writeline(OUTPUT, ll);
			end if;
			if debug > 1 and last = '1' then
				write(ll, state_t'image(c.state) & " => ");
				write(ll, state_t'image(f.state));
				writeline(OUTPUT, ll);
			end if;
		end if;
		-- synthesis translate_on
	end procedure;
begin
	assert N >= 8                      report "CPU Width too small: N >= 8"    severity failure;
	assert not (ie = '1' and oe = '1') report "input/output at the same time"  severity failure;
	assert not (ie = '1' and ae = '1') report "input whilst changing address"  severity failure;
	assert not (oe = '1' and ae = '1') report "output whilst changing address" severity failure;

	adder (add1, add2, acin, ares, acout);           -- shared adder
	cmd   <= cmd_t'val(to_integer(unsigned(c.cmd))); -- used for debug purposes
	last4 <= c.dline(c.dline'high - 4) after delay;  -- processing last four bits?
	last  <= c.dline(c.dline'high)     after delay;  -- processing last bit?

	process (clk, rst) begin
		-- Most variables are not reset here, instead only the delay line
		-- needs to be and the state-machine, making the reset smaller and simpler.
		if rst = '1' and asynchronous_reset then
			c.dline <= (others => '0') after delay; -- parallel reset!
			c.state <= RESET after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c.dline <= (others => '0') after delay;
				c.state <= RESET after delay;
			else
				-- These are just assertions/debug logging, they are not required for
				-- running, but we can make sure there are no unexpected state transitions,
				-- and report on the internal state.
				print_debug_info;
				if c.state = RESET   and last = '1' then assert f.state = FETCH;   end if;
				if c.state = LOAD    and last = '1' then assert f.state = ADVANCE; end if;
				if c.state = STORE   and last = '1' then assert f.state = ADVANCE; end if;
				if c.state = ADVANCE and last = '1' then assert f.state = FETCH;   end if;
				if c.state = HALT then assert f.state = HALT; end if;
				if c.state = EXECUTE and last = '1' then
					assert f.state = ADVANCE or f.state = LOAD or f.state = STORE or f.state = FETCH;
				end if;
			end if;
			assert not (c.first xor f.dline(0) = '1') report "first/dline";
		end if;
	end process;

	process (i, c, cmd, ares, acout, last, last4) begin
		o       <= '0' after delay;
		a       <= '0' after delay;
		ie      <= '0' after delay;
		ae      <= '0' after delay;
		oe      <= '0' after delay;
		stop    <= '0' after delay;
		add1    <= '0' after delay;
		add2    <= '0' after delay;
		acin    <= '0' after delay;
		f       <= c after delay;
		f.dline <= c.dline(c.dline'high - 1 downto 0) & "0" after delay;

		-- The delay line should contain zero bits or one bit only, depending
		-- on the systems state.
		if c.first then
			assert bit_count(c.dline) = 0 report "too many dline bits";
		else
			assert bit_count(c.dline) = 1 report "missing dline bit";
		end if;

		-- The processor works by using a delay line (shift register) to
		-- sequence actions, the top four bits are used for the
		-- instruction (and if the highest bit is set indirection
		-- is _not_ allowed), with the lowest twelve bits as an operand
		-- to use as a literal value or an address.
		--
		-- As such, we will want to trigger actions when processing the first
		-- bit, the last four bits and the last bit.
		--
		-- This delay line is used to save gates as opposed using a counter,
		-- which would require an adder (but not a comparator - we could check
		-- whether individual bits are set because all the comparisons are
		-- against power of two values).
		--
		if last = '1' then
			f.state <= c.choice after delay;
			f.first <= true     after delay;
			f.last4 <= false    after delay;
			-- This is a bit of a hack, in order to place it in its proper
			-- place within the 'FETCH' state we would need to move the
			-- 'indirection allowed on instruction' bit from the highest
			-- bit to a lower bit so we can perform the state decision before
			-- the bit is being processed.
			if i = '0' and c.state = FETCH then
				f.indir <= true after delay;
				f.state <= INDIRECT after delay; -- Override FETCH Choice!
			end if;
		elsif last4 = '1' then
			f.last4 <= true after delay;
		end if;

		-- Each state lasts N (which defaults to 16) + 1 cycles.
		-- Of note: we could make the FETCH state last only 4 + 1 cycles
		-- and merge the operand fetching in FETCH (and OPERAND state) into
		-- the 'EXECUTE' state.
		case c.state is
		when RESET   =>
			f.choice <= FETCH;
			if c.first then
				f.dline(0)  <= '1'   after delay;
				f.first     <= false after delay;
			else
				ae      <= '1' after delay;
				f.acc   <= "0" & c.acc(c.acc'high downto 1) after delay;
				f.pc    <= "0" & c.pc (c.pc'high  downto 1) after delay;
				f.op    <= "0" & c.op (c.op'high  downto 1) after delay;
				f.flags <= "0" & c.flags(c.flags'high downto 1) after delay;
			end if;
		-- When in the running state all state transitions pass through FETCH.
		-- FETCH does what you expect from it, it fetches the instruction. It also
		-- partially decodes it and sets flags that the accumulator depends on.
		--
		-- What is meant by partially decoding is this; it is determined if we
		-- should go to the INDIRECT state next or to the EXECUTE state, also
		-- it is determined whether an I/O operation should be performed for those
		-- instructions capable of doing I/O.
		when FETCH   =>
			if c.first then
				f.dline(0)   <= '1'    after delay;
				f.first      <= false  after delay;
				f.indir      <= false  after delay;
				f.flags(Z)   <= '1'    after delay;
			else
				ie           <= '1' after delay;

				if c.acc(0) = '1' then -- determine flag status before EXECUTE
					f.flags(Z) <= '0' after delay;
				end if;
				f.acc <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;

				if not c.last4 then
					f.op    <= i & c.op(c.op'high downto 1) after delay;
				else
					f.cmd   <= i   & c.cmd(c.cmd'high downto 1) after delay;
					f.op    <= "0" & c.op (c.op'high  downto 1) after delay;
				end if;
			end if;

			f.flags(Ng)  <= c.acc(0) after delay; -- contains highest bit when 'last' is true

			-- NB. 'f.choice' may be overwritten for INDIRECT.
			   if c.flags(HLT) = '1' then
				f.choice <= HALT after delay;
			elsif c.flags(R) = '1' then
				f.choice <= RESET after delay;
			else
				f.choice <= EXECUTE after delay;
			end if;
		-- INDIRECT is only used for instructions that allow for indirection
		-- (i.e. All those instructions in which the top bit is not set).
		-- The indirection adds 2*(N+1) cycles to the instruction so is quite expensive.
		--
		-- We could avoid having this state and CPU functionality if we were to
		-- make use of self-modifying code, however that would make programming the CPU
		-- more difficult. (N.B As of 2023, The project <https://github.com/howerj/subleq>
		-- makes heavy use of self modifying code to bring a Forth interpreter to a
		-- single instruction set computer (SUBLEQ), it is not too difficult).
		--
		when INDIRECT =>
			assert c.cmd(c.cmd'high) = '0' severity error;
			f.choice <= EXECUTE after delay;
			if c.first then
				f.dline(0)  <= '1'   after delay;
				f.first     <= false after delay;
			else
				ae       <=     '1' after delay;
				a        <= c.op(0) after delay;
				f.op     <=     "0" & c.op(c.op'high downto 1) after delay;
				f.choice <= OPERAND after delay;
			end if;
		-- OPERAND fetches the operand *again*, this time using the operand
		-- acquired in EXECUTE, the address being set in the previous INDIRECT state.
		when OPERAND =>
			f.choice <= EXECUTE after delay;
			if c.first then
				f.dline(0) <= '1'   after delay;
				f.first    <= false after delay;
			else
				ie      <= '1' after delay;
				f.op    <= i & c.op(c.op'high downto 1) after delay;
			end if;
		-- The EXECUTE state implements the ALU. It is the most seemingly the
		-- most complex state, but it is not (FETCH is more difficult to
		-- understand).
		when EXECUTE =>
			assert not (c.flags(Z) = '1' and c.flags(Ng) = '1') report "zero and negative?";
			f.choice     <= ADVANCE after delay;
			if c.first then
				f.dline(0)  <= '1'   after delay;
				f.first     <= false after delay;
				if cmd = iADD then f.flags(Cy) <= '0' after delay; end if;
				-- 'tcarry' is added to the program counter in the ADVANCE
				-- state, instructions that affect the program counter clear
				-- it (such as iJUMP, and iJUMPZ/iSET (conditionally).
				f.tcarry    <= '1'   after delay;
			else
				case cmd is -- ALU
				when iOR =>
					f.op  <= "0" & c.op (c.op'high  downto 1) after delay;
					f.acc <= (c.op(0) or c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
				when iAND =>
					f.acc <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
					if (not c.last4) or c.indir then
						f.op  <= "0" & c.op (c.op'high downto 1) after delay;
						f.acc <= (c.op(0) and c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
					end if;
				when iXOR =>
					f.op  <= "0" & c.op (c.op'high downto 1) after delay;
					f.acc <= (c.op(0) xor c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
				when iADD =>
					f.acc <= "0" & c.acc(c.acc'high downto 1) after delay;
					f.op  <= "0" & c.op(c.op'high downto 1)   after delay;
					add1  <=    c.acc(0) after delay;
					add2  <=     c.op(0) after delay;
					acin  <= c.flags(Cy) after delay;
					f.acc(f.acc'high) <= ares after delay;
					f.flags(Cy) <= acout after delay;
				-- A barrel shifter is usually quite an expensive piece of hardware,
				-- but it ends up being quite cheap for obvious reasons. We could
				-- dispense with both shifts and have a rotate (either left or right)
				-- by number of bits sets, this is conjunction with an "iAND" instruction
				-- to mask off bits is all we really would need.
				when iLSHIFT =>
					if c.op(0) = '1' then
						f.acc  <= c.acc(c.acc'high - 1 downto 0) & "0" after delay;
					end if;
					f.op   <= "0" & c.op (c.op'high downto 1) after delay;
				when iRSHIFT =>
					if c.op(0) = '1' then
						f.acc  <= "0" & c.acc(c.acc'high downto 1) after delay;
					end if;
					f.op   <= "0" & c.op (c.op'high downto 1) after delay;
				-- We have two sets of LOAD/STORE instructions, one set which
				-- optionally respects the indirect flag, and one set (the latter)
				-- which never does. This allows us to perform direct LOAD/STORES
				-- when the indirect flag is on.
				when iLOAD =>
					ae       <=     '1' after delay;
					a        <= c.op(0) after delay;
					f.op     <= c.op(0) & c.op(c.op'high downto 1) after delay;
					f.choice <= LOAD after delay;
				when iSTORE =>
					ae       <=     '1' after delay;
					a        <= c.op(0) after delay;
					f.op     <=     "0" & c.op(c.op'high downto 1) after delay;
					f.choice <= STORE after delay;
				when iLOADC =>
					ae       <=     '1' after delay;
					a        <= c.op(0) after delay;
					f.op     <= c.op(0) & c.op(c.op'high downto 1) after delay;
					f.choice <= LOAD after delay;
				when iSTOREC =>
					ae       <=     '1' after delay;
					a        <= c.op(0) after delay;
					f.op     <=     "0" & c.op(c.op'high downto 1) after delay;
					f.choice <= STORE after delay;
				when iLITERAL =>
					f.acc  <= c.op(0) & c.acc(c.acc'high downto 1) after delay;
					f.op   <=     "0" & c.op (c.op'high downto 1)  after delay;
				when iUNUSED =>
				-- We could use this if we need to extend the instruction set
				-- for any reason. I cannot think of a good one that justifies the
				-- cost of a new instruction. So this will remain blank for now.
				--
				-- Candidates for an instruction include:
				--
				-- * Arithmetic Right Shift
				-- * Subtraction
				-- * Swap Low/High Byte (may be difficult to implement)
				-- * Increment or decrement (for simulating stacks)
				--
				-- However, this instruction may not have its indirection bit set,
				-- This would not be a problem for the swap instruction. Alternatively
				-- an 'add-constant' could be added.
				--
				when iJUMP =>
					ae       <=     '1' after delay;
					a        <= c.op(0) after delay;
					f.op     <=     "0" & c.op(c.op'high downto 1) after delay;
					f.pc     <= c.op(0) & c.pc(c.pc'high downto 1) after delay;
					f.choice <= FETCH after delay;
				when iJUMPZ =>
					if c.flags(Z) = jumpz then
						ae     <=     '1' after delay;
						a      <= c.op(0) after delay;
						f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
						f.pc   <= c.op(0) & c.pc(c.pc'high downto 1) after delay;
						f.choice <= FETCH after delay;
					end if;
				-- N.B. We could probably eliminate these instructions by mapping
				-- the registers into the memory address space, this would free
				-- up another two instructions, and potentially simplify the CPU.
				--
				when iSET =>
					if c.op(0) = '0' then
						-- NB. We could set the address directly here and
						-- go to FETCH but that costs us too much time and gates.
						f.pc     <= c.acc(0) & c.pc(c.pc'high downto 1) after delay;
						f.tcarry <= '0' after delay;
					else
						f.flags  <= c.acc(0) & c.flags(c.flags'high downto 1) after delay;
					end if;
					f.acc    <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
				when iGET =>
					if c.op(0) = '0' then
						f.acc    <= c.pc(0) & c.acc(c.acc'high downto 1) after delay;
						f.pc     <= c.pc(0) & c.pc(c.pc'high downto 1)   after delay;
					else
						f.acc    <= c.flags(0) & c.acc(c.acc'high downto 1)     after delay;
						f.flags  <= c.flags(0) & c.flags(c.flags'high downto 1) after delay;
					end if;
				end case;
			end if;
		-- Unfortunately we cannot perform a load or a store whilst we are
		-- performing an EXECUTE, so we require STORE and LOAD states to do
		-- more work after a LOAD or STORE instruction.
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
		-- ADVANCE reuses our adder in iADD to add one to the program counter.
		-- most instructions go through this one to advance the program counter.
		--
		-- 'iSET' also goes through this state to save space, but it sets 'tcarry'
		-- to zero avoid advancing the set value.
		when ADVANCE =>
			f.choice <= FETCH after delay;
			if c.first then
				f.dline(0) <= '1'   after delay;
				f.first    <= false after delay;
			else
				f.pc <= "0" & c.pc(c.pc'high downto 1) after delay;
				add1 <= c.pc(0)  after delay;
				-- A 'skip' facility could be made by optionally setting this to '1'
				-- for the first cycle, incrementing the program counter by 2.
				add2 <= '0'      after delay;
				acin <= c.tcarry after delay;
				f.pc(f.pc'high) <= ares  after delay;
				a               <= ares  after delay;
				f.tcarry        <= acout after delay;
				ae   <= '1' after delay;
			end if;
		-- STOP, for it is the time of Hammers.
		when HALT => stop <= '1' after delay;
		end case;
	end process;
end architecture;

