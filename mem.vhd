library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity mem is 
	generic (
		asynchronous_reset: boolean  := true; -- use asynchronous reset if true, synchronous if false
		delay:              time     := 0 ns; -- simulation only, gate delay
		file_name:          string;
		W:                  positive;
		N:                  positive);
	port (
		clk:         in std_ulogic;
		rst:         in std_ulogic;
		i, a:        in std_ulogic;
		o:          out std_ulogic;
   		oe, ie, ae:  in std_ulogic);
end;

architecture rtl of mem is
	constant data_length: positive := N;
	constant addr_length: positive := W;
	constant ram_size: positive := 2 ** addr_length;

	type ram_type is array ((ram_size - 1 ) downto 0) of std_ulogic_vector(data_length - 1 downto 0);

	function hex_char_to_std_ulogic_vector(hc: character) return std_ulogic_vector is
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


	impure function initialize_ram(the_file_name: in string) return ram_type is
		variable ram_data:   ram_type;
		file     in_file:    text is in the_file_name;
		variable input_line: line;
		variable tmp:        bit_vector(data_length - 1 downto 0);
		variable c:          character;
		variable slv:        std_ulogic_vector(data_length - 1 downto 0);
	begin
		for k in 0 to ram_size - 1 loop
			if not endfile(in_file) then
				readline(in_file,input_line);
					assert (data_length mod 4) = 0 report "(data_length%4)!=0" severity failure;
					for j in 1 to (data_length/4) loop
						c:= input_line((data_length/4) - j + 1);
						slv((j*4)-1 downto (j*4)-4) := hex_char_to_std_ulogic_vector(c);
					end loop;
					ram_data(k) := slv;
			else
				ram_data(k) := (others => '0');
			end if;
		end loop;
		file_close(in_file);
		return ram_data;
	end function;

	shared variable ram: ram_type := initialize_ram(file_name);

	signal a_c, a_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal i_c, i_n: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal o_c, o_n: std_ulogic_vector(N - 1 downto 0) := x"4003";
begin
	process (clk, rst)
	begin
		if rst = '1' and asynchronous_reset then
			a_c <= (others => '0'); -- parallel!
			i_c <= (others => '0'); -- parallel!
			o_c <= (others => '0'); -- parallel!
		elsif rising_edge(clk) then
			if rst = '1' and not asynchronous_reset then
				a_c <= (others => '0'); -- parallel!
				i_c <= (others => '0'); -- parallel!
				o_c <= (others => '0'); -- parallel!
			else
				a_c <= a_n;
				i_c <= i_n;
				o_c <= o_n;

			end if;
		end if;
	end process;

	process (a_c, i_c, o_c, i, a, oe, ie, ae)
	begin
		a_n <= a_c;
		i_n <= i_c;
		o_n <= o_c;
		o   <= o_c(0);
		if ae = '1' then a_n <= a      & a_c(a_c'high downto 1); end if;
		if oe = '1' then o_n <= o_c(0) & o_c(o_c'high downto 1); end if;
		if ie = '1' then i_n <= i      & i_c(i_c'high downto 1); end if;

		if ie = '1' and ae = '0' then
			ram(to_integer(unsigned(a_c(a_c'high - 4 downto 0)))) := i_c;
		end if;

		if oe = '0' and ae = '0' then
			o_n <= ram(to_integer(unsigned(a_c(a_c'high - 4 downto 0))));
		end if;

	end process;

end architecture;

