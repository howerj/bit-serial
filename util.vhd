library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package util is
	-- Not all modules will need every generic specified here, even so it
	-- is easier to group the common generics in one structure.
	type common_generics is record
		clock_frequency:    positive; -- clock frequency of module clock
		delay:              time;     -- gate delay for simulation purposes
		asynchronous_reset: boolean;  -- use asynchronous reset if true
	end record;

	constant default_settings: common_generics := (
		clock_frequency    => 100_000_000,
		delay              => 10 ns,
		asynchronous_reset => true
	);

	component fifo is
		generic (g: common_generics;
			data_width:  positive;
			fifo_depth:  positive;
			read_first:  boolean := true);
		port (
			clk:   in  std_ulogic;
			rst:   in  std_ulogic;
			di:    in  std_ulogic_vector(data_width - 1 downto 0);
			we:    in  std_ulogic;
			re:    in  std_ulogic;
			do:    out std_ulogic_vector(data_width - 1 downto 0);

			-- optional
			full:  out std_ulogic := '0';
			empty: out std_ulogic := '1');
	end component;

	function parity(slv:std_ulogic_vector; even: boolean) return std_ulogic;
	function parity(slv:std_ulogic_vector; even: std_ulogic) return std_ulogic;
end;

package body util is
	function parity(slv: std_ulogic_vector; even: boolean) return std_ulogic is
		variable z: std_ulogic := '0';
	begin
		if not even then
			z := '1';
		end if;
		for i in slv'range loop
			z := z xor slv(i);
		end loop;
		return z;
	end;

	function parity(slv:std_ulogic_vector; even: std_ulogic) return std_ulogic is
		variable z: boolean := false;
	begin
		if even = '1' then
			z := true;
		end if;
		return parity(slv, z);
	end;
end;

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.common_generics;

entity fifo is
	generic (g: common_generics; 
		data_width: positive; 
		fifo_depth: positive;
		read_first: boolean := true);
	port (
		clk:   in  std_ulogic;
		rst:   in  std_ulogic;
		di:    in  std_ulogic_vector(data_width - 1 downto 0);
		we:    in  std_ulogic;
		re:    in  std_ulogic;
		do:    out std_ulogic_vector(data_width - 1 downto 0);

		-- optional
		full:  out std_ulogic := '0';
		empty: out std_ulogic := '1');
end fifo;

architecture behavior of fifo is
	type fifo_data_t is array (0 to fifo_depth - 1) of std_ulogic_vector(di'range);
	signal data: fifo_data_t := (others => (others => '0'));
	function rindex_init return integer is
	begin
		if read_first then
			return 0;
		end if;
		return fifo_depth - 1;
	end function;

	signal count:  integer range 0 to fifo_depth := 0;
	signal windex: integer range 0 to fifo_depth - 1 := 0;
	signal rindex: integer range 0 to fifo_depth - 1 := rindex_init;

	signal is_full:  std_ulogic := '0';
	signal is_empty: std_ulogic := '1';
begin
	-- TODO: Allow read to be configurable to next or current rindex
	do       <= data(rindex) after g.delay;
	full     <= is_full after g.delay;  -- buffer these bad boys
	empty    <= is_empty after g.delay;
	is_full  <= '1' when count = fifo_depth else '0' after g.delay;
	is_empty <= '1' when count = 0          else '0' after g.delay;

	process (rst, clk) is
	begin
		if rst = '1' and g.asynchronous_reset then
			windex <= 0 after g.delay;
			count  <= 0 after g.delay;
			rindex <= rindex_init after g.delay;
		elsif rising_edge(clk) then
			if rst = '1' and not g.asynchronous_reset then
				windex <= 0 after g.delay;
				count  <= 0 after g.delay;
				rindex <= rindex_init after g.delay;
			else
				if we = '1' and re = '0' then
					if is_full = '0' then
						count <= count + 1 after g.delay;
					end if;
				elsif we = '0' and re = '1' then
					if is_empty = '0' then
						count <= count - 1 after g.delay;
					end if;
				end if;

				if re = '1' and is_empty = '0' then
					if rindex = (fifo_depth - 1) then
						rindex <= 0 after g.delay;
					else
						rindex <= rindex + 1 after g.delay;
					end if;
				end if;

				if we = '1' and is_full = '0' then
					if windex = (fifo_depth - 1) then
						windex <= 0 after g.delay;
					else
						windex <= windex + 1 after g.delay;
					end if;
					data(windex) <= di after g.delay;
				end if;
			end if;
		end if;
	end process;
end behavior;

