-- File:        bit.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/bit-serial
-- License:     MIT
-- Description: An N-bit, simple and small bit serial CPU
--
-- TODO: Add interrupts, some form of call/return, and
-- a built in timer with clock enable/interrupt generation
-- on comparison to a register.
-- TODO: It might be best to experiment with the instruction
-- set more, such as treating the operand as an address to load
-- instead of using it directly (which may require another state).
-- This could be selected for with a flag.
library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- for debug only, not needed for synthesis

entity bcpu is 
	generic (
		asynchronous_reset: boolean  := true; -- use asynchronous reset if true, synchronous if false
		delay:              time     := 0 ns; -- simulation only, gate delay
		N:                  positive := 16;
	
		parity:             std_ulogic := '0';   -- set parity (even/odd) of parity flag
		jumpz:              std_ulogic := '1';   -- jump on zero = '1', jump on non-zero = '0'
		debug:              boolean    := false  -- if true, debug statements will be printed
	);
	port (
		clk:         in std_ulogic;
		rst:         in std_ulogic;
		i:           in std_ulogic;
		o, a:       out std_ulogic;
   		oe, ie, ae: buffer std_ulogic;
		stop:       out std_ulogic);
end;

architecture rtl of bcpu is
	type state_t is (RESET, FETCH, EXECUTE, STORE, LOAD, ADVANCE, HALT);
	type cmd_t is (
		iOR,     iAND,    iXOR,     iADD, 
		iROTL,   iROTR,   iIN,      iOUT,
		iLOAD,   iSTORE,  iLITERAL, iFLAGS, 
		iJUMP,   iJUMPZ,  iJUMPI,   iPC
	);
	constant Cy:     integer :=  0; -- Carry; set by addition
	constant Z:      integer :=  1; -- Accumulator is zero
	constant Ng:     integer :=  2; -- Accumulator is negative
	constant PAR:    integer :=  3; -- Parity of accumulator
	constant ROT:    integer :=  4; -- Use rotate instead of shift
	constant R:      integer :=  5; -- Reset CPU
	constant UN:     integer :=  6; -- Unused flag
	constant HLT:    integer :=  7; -- Halt CPU

	type registers_t is record
		state:  state_t;    -- state machine register
		choice: state_t;    -- computed next state
		first:  boolean;    -- First flag, for setting up an instruction
		last4:  boolean;    -- Are we processing the last 4 bits of the instruction?
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
		tcarry => 'X',
		dline  => (others => '0'),
		acc    => (others => 'X'),
		pc     => (others => 'X'),
		op     => (others => 'X'),
		flags  => (others => 'X'),
		cmd    => (others => 'X'));

	signal c, f: registers_t := registers_default; -- BCPU registers
	signal cmd: cmd_t; -- Shows up nicely in traces as an enumerated value
	signal add1, add2, acin, ares, acout: std_ulogic; -- shared adder signals
	signal last4, last:                   std_ulogic; -- state sequence signals

	procedure adder (x, y, cin: in std_ulogic; signal sum, cout: out std_ulogic) is
	begin
		sum  <= x xor y xor cin after delay;
		cout <= (x and y) or (cin and (x xor y)) after delay;
	end procedure;

	function bit_count(bc: in std_ulogic_vector) return natural is -- used for assertions
		variable count: natural := 0;
	begin
		for index in bc'range loop
			if bc(index) = '1' then
				count := count + 1;
			end if;
		end loop;
		return count;
	end function;

	procedure reportln is 
		function stringify(slv: in std_ulogic_vector) return string is
		begin
			return integer'image(to_integer(unsigned(slv)));
		end function;

		variable ll: line;
	begin
		-- synthesis translate_off
		if debug then
			write(ll, stringify(c.pc) & ": ");
			write(ll, cmd_t'image(cmd) & " ");
			write(ll, stringify(c.op) & " ");
			write(ll, stringify(c.acc) & " ");
			write(ll, stringify(c.flags) & " ");
			writeline(OUTPUT, ll);
		end if;
		-- synthesis translate_on
	end procedure;
begin
	assert N >= 8                      report "CPU Width too small: N >= 8"   severity failure;
	assert not (ie = '1' and oe = '1') report "input/output at the same time" severity failure;
	assert not (ie = '1' and ae = '1') report "input whilst changing address" severity failure;
	adder (add1, add2, acin, ares, acout);           -- shared adder
	cmd   <= cmd_t'val(to_integer(unsigned(c.cmd))); -- used for debug purposes
	last4 <= c.dline(c.dline'high - 4) after delay;  -- processing last four bits?
	last  <= c.dline(c.dline'high)     after delay;  -- processing last bit?

	process (clk, rst)
	begin
		if rst = '1' and asynchronous_reset then
			c.dline <= (others => '0') after delay;
			c.state <= RESET after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c.dline <= (others => '0') after delay;
				c.state <= RESET after delay;
			else
				if c.state = EXECUTE and c.first then reportln; end if;
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

	process (i, c, cmd, ares, acout, last, last4)
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
		f        <= c after delay;
		f.dline  <= c.dline(c.dline'high - 1 downto 0) & "0" after delay;

		if c.first then
			assert bit_count(c.dline) = 0 report "too many dline bits";
		else
			assert bit_count(c.dline) = 1 report "missing dline bit";
		end if;

		if last = '1' then
			f.state <= c.choice after delay;
			f.first <= true     after delay;
			f.last4 <= false    after delay;
		end if;

		if last4 = '1' then
			f.last4 <= true after delay;
		end if;

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
		when FETCH   =>
			assert not (c.flags(Z) = '1' and c.flags(Ng) = '1') report "zero and negative?";
			if c.first then
				f.dline(0)   <= '1'    after delay;
				f.first      <= false  after delay;
				f.flags(Z)   <= '1'    after delay;
				f.flags(PAR) <= parity after delay;
			else
				ie          <= '1' after delay;

				if c.acc(0) = '1' then -- determine flag status before EXECUTE
					f.flags(Z) <= '0' after delay;
				end if;
				f.flags(PAR) <= c.acc(0) xor c.flags(PAR) after delay;
				f.acc <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;

				if not c.last4 then
					f.op    <= i & c.op(c.op'high downto 1) after delay;
				else
					f.cmd   <= i   & c.cmd(c.cmd'high downto 1) after delay;
					f.op    <= "0" & c.op (c.op'high  downto 1) after delay;
				end if;
			end if;
			
			f.flags(Ng)  <= c.acc(c.acc'high) after delay;

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
				f.dline(0)  <= '1'   after delay;
				f.first     <= false after delay;
			else
				case cmd is -- ALU
				when iOR =>
					f.op  <= "0" & c.op (c.op'high  downto 1) after delay;
					f.acc <= (c.op(0) or c.acc(0)) & c.acc(c.acc'high downto 1) after delay;
				when iAND =>
					f.acc <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
					if not c.last4 then
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
				when iROTL   =>
					if c.op(0) = '1' then
						-- f.acc  <= c.acc(c.acc'high - 1 downto 0) & "0" after delay;
						-- if c.flags(ROT) = '1' then
							f.acc  <= c.acc(c.acc'high - 1 downto 0) & c.acc(0) after delay;
						-- end if;
					end if;
					f.op   <= "0" & c.op (c.op'high downto 1) after delay;
				when iROTR   =>
					if c.op(0) = '1' then
						-- f.acc  <= "0" & c.acc(c.acc'high downto 1) after delay;
						-- if c.flags(ROT) = '1' then
							f.acc  <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
						-- end if;
					end if;
					f.op   <= "0" & c.op (c.op'high downto 1) after delay;
				when iIN =>
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					if last = '1' then
						a <= '1' after delay;
					end if;
					f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
					f.choice <= LOAD after delay;

				when iOUT =>
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					if last = '1' then
						a <= '1' after delay;
					end if;
					f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
					f.choice <= STORE after delay;

				when iLOAD =>
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
					f.choice <= LOAD after delay;
				when iSTORE =>
					ae     <=     '1' after delay;
					a      <= c.op(0) after delay;
					f.op   <=     "0" & c.op(c.op'high downto 1) after delay;
					f.choice <= STORE after delay;
				when iLITERAL =>
					f.acc  <= c.op(0) & c.acc(c.acc'high downto 1) after delay;
					f.op   <=     "0" & c.op (c.op'high downto 1)  after delay;
				when iFLAGS =>
					f.acc   <= c.flags(0) & c.acc(c.acc'high downto 1) after delay;
					f.flags <= (((not c.op(0)) and c.acc(0)) or (c.op(0) and c.flags(0))) & 
						   c.flags(c.flags'high downto 1) after delay;
					f.op    <=        "0" & c.op(c.op'high downto 1) after delay;

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
				when iJUMPI =>
					f.pc     <= c.acc(0) & c.pc(c.pc'high downto 1) after delay;
					f.acc    <= c.acc(0) & c.acc(c.acc'high downto 1) after delay;
					f.choice <= FETCH after delay;
				when iPC =>
					f.acc    <= c.pc(0) & c.acc(c.acc'high downto 1) after delay;
					f.pc     <= c.pc(0) & c.pc(c.pc'high downto 1) after delay;
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
				f.dline(0) <= '1'   after delay;
				f.first    <= false after delay;
				f.tcarry   <= '0'   after delay;
			else
				f.pc <= "0" & c.pc(c.pc'high downto 1) after delay;
				add1 <=    c.pc(0) after delay;
				add2 <= c.dline(0) after delay;
				acin <=   c.tcarry after delay;
				f.pc(f.pc'high) <= ares  after delay;
				a               <= ares  after delay;
				f.tcarry        <= acout after delay;
				ae   <= '1' after delay;
			end if;
		when HALT => stop <= '1' after delay;
		end case;
	end process;
end architecture;

