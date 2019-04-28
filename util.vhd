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
		delay              => 0 ns,
		asynchronous_reset => true
	);

	type file_format is (FILE_HEX, FILE_BINARY, FILE_NONE);

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

	component single_port_block_ram is
	generic (g: common_generics;
		addr_length: positive    := 12;
		data_length: positive    := 16;
		file_name:   string      := "memory.bin";
		file_type:   file_format := FILE_BINARY);
	port (
		clk:  in  std_ulogic;
		dwe:  in  std_ulogic;
		dre:  in  std_ulogic;
		addr: in  std_ulogic_vector(addr_length - 1 downto 0);
		din:  in  std_ulogic_vector(data_length - 1 downto 0);
		dout: out std_ulogic_vector(data_length - 1 downto 0) := (others => '0'));
	end component;

	function parity(slv:std_ulogic_vector; even: boolean) return std_ulogic;
	function parity(slv:std_ulogic_vector; even: std_ulogic) return std_ulogic;
	function hex_char_to_std_ulogic_vector_tb(hc: character) return std_ulogic_vector;
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

	function hex_char_to_std_ulogic_vector_tb(hc: character) return std_ulogic_vector is
		variable slv: std_ulogic_vector(3 downto 0);
	begin
		case hc is
		when '0' => slv := "0000";
		when '1' => slv := "0001";
		when '2' => slv := "0010";
		when '3' => slv := "0011";
		when '4' => slv := "0100";
		when '5' => slv := "0101";
		when '6' => slv := "0110";
		when '7' => slv := "0111";
		when '8' => slv := "1000";
		when '9' => slv := "1001";
		when 'A' => slv := "1010";
		when 'a' => slv := "1010";
		when 'B' => slv := "1011";
		when 'b' => slv := "1011";
		when 'C' => slv := "1100";
		when 'c' => slv := "1100";
		when 'D' => slv := "1101";
		when 'd' => slv := "1101";
		when 'E' => slv := "1110";
		when 'e' => slv := "1110";
		when 'F' => slv := "1111";
		when 'f' => slv := "1111";
		when others => slv := "XXXX";
		end case;
		assert (slv /= "XXXX") report " not a valid hex character: " & hc  severity failure;
		return slv;
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

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.util.all;

entity single_port_block_ram is
	generic (g: common_generics;
		addr_length: positive    := 12;
		data_length: positive    := 16;
		file_name:   string      := "memory.bin";
		file_type:   file_format := FILE_BINARY);
	port (
		clk:  in  std_ulogic;
		dwe:  in  std_ulogic;
		dre:  in  std_ulogic;
		addr: in  std_ulogic_vector(addr_length - 1 downto 0);
		din:  in  std_ulogic_vector(data_length - 1 downto 0);
		dout: out std_ulogic_vector(data_length - 1 downto 0) := (others => '0'));
end entity;

architecture behav of single_port_block_ram is
	constant ram_size: positive := 2 ** addr_length;

	type ram_type is array ((ram_size - 1 ) downto 0) of std_ulogic_vector(data_length - 1 downto 0);

	impure function initialize_ram(the_file_name: in string; the_file_type: in file_format) return ram_type is
		variable ram_data:   ram_type;
		file     in_file:    text is in the_file_name;
		variable input_line: line;
		variable tmp:        bit_vector(data_length - 1 downto 0);
		variable c:          character;
		variable slv:        std_ulogic_vector(data_length - 1 downto 0);
	begin
		for i in 0 to ram_size - 1 loop
			if the_file_type = FILE_NONE then
				ram_data(i):=(others => '0');
			elsif not endfile(in_file) then
				readline(in_file,input_line);
				if the_file_type = FILE_BINARY then
					read(input_line, tmp);
					ram_data(i) := std_ulogic_vector(to_stdlogicvector(tmp));
				elsif the_file_type = FILE_HEX then -- hexadecimal
					assert (data_length mod 4) = 0 report "(data_length%4)!=0" severity failure;
					for j in 1 to (data_length/4) loop
						c:= input_line((data_length/4) - j + 1);
						slv((j*4)-1 downto (j*4)-4) := hex_char_to_std_ulogic_vector_tb(c);
					end loop;
					ram_data(i) := slv;
				else
					report "Incorrect file type given: " & file_format'image(the_file_type) severity failure;
				end if;
			else
				ram_data(i) := (others => '0');
			end if;
		end loop;
		file_close(in_file);
		return ram_data;
	end function;

	shared variable ram: ram_type := initialize_ram(file_name, file_type);

begin
	block_ram: process(clk)
	begin
		if rising_edge(clk) then
			if dwe = '1' then
				ram(to_integer(unsigned(addr))) := din;
			end if;

			if dre = '1' then
				dout <= ram(to_integer(unsigned(addr))) after g.delay;
			else
				dout <= (others => '0') after g.delay;
			end if;
		end if;
	end process;
end architecture;


