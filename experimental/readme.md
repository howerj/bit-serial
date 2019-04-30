
		                           ____   ___  ____  _  _                                     
		                          (  _ \ / __)(  _ \/ )( \                                    
		                           ) _ (( (__  ) __/) \/ (                                    
		                          (____/ \___)(__)  \____/                                    
		  __     ____  __  ____    ____  ____  ____  __   __   __       ___  ____  _  _       
		 / _\   (  _ \(  )(_  _)  / ___)(  __)(  _ \(  ) / _\ (  )     / __)(  _ \/ )( \      
		/    \   ) _ ( )(   )(    \___ \ ) _)  )   / )( /    \/ (_/\  ( (__  ) __/) \/ (      
		\_/\_/  (____/(__) (__)   (____/(____)(__\_)(__)\_/\_/\____/   \___)(__)  \____/



| Project   | Bit-Serial CPU in VHDL                 |
| --------- | -------------------------------------- |
| Author    | Richard James Howe                     |
| Copyright | 2019 Richard James Howe                |
| License   | MIT                                    |
| Email     | howe.r.j.89@gmail.com                  |
| Website   | <https://github.com/howerj/bit-serial> |

*Processing data one bit at a time, since 2019*.

# Introduction

This is a project for a [bit-serial CPU][], which is a CPU that has an architecture
which processes a single bit at a time instead of in parallel like a normal
CPU. This allows the CPU itself to be a lot smaller, the penalty is that it is
a lot slower. The CPU itself is called *bcpu*.

The CPU is incredibly basic, lacking support for features required to support
higher level programming (such as function calls). Instead such features can 
be emulated if they are needed. If such features are needed, or faster
throughput (whilst still remaining quite small) other [Soft-Core][] CPUs are
available, such as the [H2][]. 

To build the assembler and C based simulator for the project, you will need a C
compiler and 'make'. To build the [VHDL][] simulator, you will need [GHDL][]
installed.

The target [FPGA][] that the system is built for is a [Spartan-6][], for a
[Nexys 3][] development board. [Xilinx ISE 14.7][] was used to build the
project.

The following 'make' targets are available:

	make

By default the [VHDL][] test bench is built and simulated in [GHDL][]. This
requires that the assembler is build, to assemble the test program [bit.asm][]
into a file readable by the simulator.

	make run

This target builds the C based simulator/assembler, assembles the test program
and runs the simulator on the assembled program.

	make simulation synthesis implementation bitfile

This builds the project for the [FPGA][].

	make upload

This uploads the project to the [Nexys 3][] board. This requires that
'djtgcfg' is installed, which is a tool provided by [Digilent][].

	make documentation

This turns this 'readme.md' file into a HTML file.

	make clean

Cleans up the project.

# CPU Specification

A quick overview of the features *bcpu*:

* A 16/12-bit CPU
* Can address 4096 16-bit values of program memory, and 8192 16-byte values
(including the 4096 16-bit values of program memory) of data and
memory mapped input/output.
* An accumulator design
* As it is a [bit-serial CPU][] it processes data a bit at a time, the
processor stays in each state for 16 clock cycles. A single instruction is
fetched and executed in 51-68 ((16 + 1)\*3 to (16 + 1) \* 4) clock cycles.
* Has add-with-carry, subtract with borrow flag, rotate and shift left/right 
instructions.
* Lacks any kind of call stack, or registers.
* Has very little CPU state; 5 x 16 bit registers, a 4-bit register, 2 x 3-bit
  register, and 2 x 1-bit register.
* Takes up very little floor space and no dedicated resources (apart from a
Block RAM for the program memory) on the [FPGA][].

The CPU is self-contained within a single file, [bit.vhd][]. It communicates to
the rest of the system in the [FPGA][] via a serial interface. Whilst the CPU
can be customized via a [VHDL][] generic to be of an arbitrary width, the rest
of the document and the toolchain assume the width has been set to 16. 

There is a single state-machine which forms the heart of the CPU, it has seven
states; 'reset', 'fetch', 'execute', 'store', 'load', 'advance' and 'halt'.

![](bcpu-0.svg)

Not shown in this diagram is the fact that all states can go back to the
'reset' state when an external reset signal is given, this reset can be
configured to be asynchronous or synchronous.

Whilst the CPU could be described as a 16-bit CPU, a more accurate description
would be that it is a hybrid 16/12-bit CPU. All instructions are composed of a
4-bit command and a 12-bit operand (even if the operand is not used).

# Instruction Set

Register Key:

* acc   - The accumulator, this is used to store the results of operations,
such as addition, or loading a value.
* pc    - The program counter, this is incremented after each instruction
is executed unless the instruction sets the program counter.
* flags - A 16-bit register containing 8-flags
* shadow - swapped with the program counter on an interrupt
* compare - Counter compare register
* count  - Counter register
* op    - A 12-bit operand which is part of every instruction.
* rotl  - rotate left, not through carry
* rotr  - rotate right, not through carry
* &lt;&lt; - shift left, not through carry
* &gt;&gt; - shift right, not through carry
* bitcount - a function returning the count of the number of set bits in a
value
* memory - the program and data memory, read/write.

The instruction set is as follows, opcode is the top four bits of every
instruction, the rest is used as a 12-bit immediate value which could be used
as a value or an address.

| Instruction | Registers / Flags Effected               | Description                       |
| ----------- | ---------------------------------------- | --------------------------------- |
|   or        | acc = acc OR op                          | OR  with 12-bit immediate value   |
|   and       | acc = acc AND (op OR $F000)              | AND with 12-bit immediate value   |
|   xor       | acc = acc XOR op                         | XOR with 12-bit immediate value   |
|   invert    | acc = INVERT acc                         | Bit-wise invert                   |
|   add       | acc = acc + op + carry                   | Add with 12-bit immediate value,  |
|             | carry = set/clr                          | Carry added in and set.           |
|   sub       | acc = (acc - op) - borrow                | Subtract with 12-bit immediate    |
|             | borrow = set/clr                         | value, borrow used and set/clr    |
|   lshift    | if alternate flag set:                   | Left rotate *OR* Left Shift by    |
|             | acc = rotl(acc, bitcount(op)             | bit-count of 12-bit operand.      |
|             | else                                     | Rotate/Shift selected by CPU flag |
|             | acc = acc &lt;&lt; bitcount(op)          |                                   |
|   rshift    | if alternate flag set:                   | Right rotate *OR* Right Shift by  |
|             | acc = rotr(acc, bitcount(op)             | bit-count of 12-bit operand.      |
|             | else                                     | Rotate/Shift selected by CPU flag |
|             | acc = acc &gt;&gt; bitcount(op)          |                                   |
|   load      | acc = memory(op OR (addr15 &lt;&lt; 15)) | Load memory location              |
|   store     | memory(op OR (addr15 &lt;&lt; 15)) = acc | Store to memory location          |
|   literal   | acc = op                                 | Load literal                      |
|   flags     | acc = flags, flags = op                  | Exchange flags with accumulator   |
|   jump      | pc = op                                  | Unconditional Jump to 12-bit      |
|             |                                          | Address                           |
|   jumpz     | if zero flag not set then:               | Conditional Jump, set Program     |
|             | pc = op                                  | Counter to 12-bit address only if |
|             |                                          | accumulator is non-zero           |
|   shadow    | if alternate flag set then:              | Swap internal registers for       |
|             | comp = acc; acc = count;                 | either the shadow register, or    |
|             | else                                     | counter/compare registers         |
|             | shadow = acc; acc = shadow;              |                                   |
|             |                                          |                                   |
|   Unused    |                                          |                                   |

The flags register contains the following flags:

| Flag-Bit | Name        | Description                    |
| -------- | ----------- | ------------------------------ |
|    0     | carry       | Carry Flag                     |
|    1     | borrow      | Borrow/Under Flow              |
|    2     | zero        | Is accumulator zero?           |
|    3     | negative    | Is accumulator negative?       |
|    4     | Parity      | Parity of accumulator          |
|    5     | Alternate   | Activate alternate instruction |
|    6     | Reset       | Set to reset the CPU           |
|    7     | Halt        | Set to halt the CPU            |
|    8     | inten       | Interrupt Enable if 1          |
|    9     | cnten       | Counter Enable                 |
|    10    | cntint      | Counter Interrupt              |
|    11    | addr15      | Top bit of LOAD and STORE      |
|  12-15   | Reserved    |                                |

The zero, parity and negative flags are updated before each instruction is
executed and depend only on the contents on the accumulator. They are updated
regardless of what instruction is executed. The carry flag is only updated by
addition, or the flags instruction, and the borrow flag only by subtraction or
the flag instruction. The flags instruction can set the zero, parity or
negative flag bits, however they will be updated right after the flags
instruction has been executed.

The Halt flag takes precedence over the Reset flag. The reset instruction
clears all of the flags, then recalculates the parity, zero and negative flags.

To connect the CPU up to the rest of the system you will need to understand the
signal timing for all of the *bcpu* input and output signals:

![BCPU Timing](bcpu-1.png)

Some notes on the timing diagram, the 'cycle' field is for illustrative
purposes only. The text in the 'cycle' field has the following meaning:

* prev: The last bit of the previous execution state.
* init: The first bit of the current execution state, this is used to set up
  the current execution state.
* 0-15: The rest of the bits to be processed for the current execution state.
* next: The first bit of the next execution state.
* rest: The rest of the bits of the next execution states.

Other useful information:

* The Least Significant Bit is transmitted first input, output and the address.
* The output signal line goes to either an output register or an address
register depending on whether 'oe' or 'ae' is selected.
* Reads and writes never happen at the same time.
* All of the enable lines ('oe', 'ie', and 'ae') are held high for exactly
16-clock cycles. Prior to this, and after it, the line are guaranteed to return
to zero for at least one clock cycle. 
* Interrupts can be triggered from an external source, or from the internal
  clock.
* Interrupts are only processed in the EXECUTE state.
* An interrupt fires only when interrupts are enabled with the correct flag.
* An interrupts firing causes interrupts to be disabled.
* An interrupts swaps the location in the shadow register with the program
  counter.

# Tool-Chain

The tool-chain is entirely contained within a single file, [bit.c][]. This
contains a simulator/debugger and an assembler for the CPU. It is capable of
producing files understandable by the [VHDL][] CPU as well, the generated file
is used for the [C][] simulation and the [VHDL][] simulation/synthesis.

The syntax of the assembler and the directives it provides are quite primitive.
The program itself is quite small (about 500 LOC), so you can read it to
understand it and extend it yourself if you need to.

The directives and commands can be split up into three groups, based on the
number of arguments they comprise; one, two or three. Only one command may be
placed on a single line. Comments begin with '#' or a ';' and continue until
the end of a line. A line is limited to 256 characters in length. All numbers
are entered in hexadecimal, numbers can instead be replaced by references
either a label or a variable. Forward references are allowed.

Directives:

| Directive              | Description                               |
| ---------------------- | ----------------------------------------- |
| i                      | Write address as a literal into memory at |
|                        | current location.                         |
| $                      | Write number as a literal into memory at  |
|                        | current location.                         |
| variable i             | Allocate space for a variable and give    |
|                        | it a name                                 |
| allocate $             | Allocate space                            |
| set $i $i              | Set label or location to value            |
| label i                | Create label at current location          |
| instruction            | Compile instruction                       |
| instruction $i         | Compile instruction with operand          |
| #                      | Comment until end of line                 |
| ;                      | Comment until end of line                 |

The arguments given to the directives in the above table can either be
hexadecimal numbers (such as '$123' or $a12'). This is shown with a '$' sign.
Or they can be a label or a variable, which is shown with a 'i' sign.

There are a few pseudo instructions:

* 'nop', which is 'or $0'
* 'clr', which is 'literal $0'

The instruction field may be one of the following; "or", "and", "xor", "invert",
"add", "sub", "lshift", "rshift", "load", "store", "literal", "flags", "jump", 
"jumpz", "14?", "15?". "14?" and "15?" correspond to the unused instructions.

To assemble a file with the toolchain:

	./bit -a bit.asm bit.hex

To run the simulator on a built hex file:

	./bit -r bit.hex

An example program:

	; set I/O register $0 to $55, then increment a variable
	; 'count' that starts at '$3' until it exceeds '$F'. Then
	; Halt the CPU.

		variable count
	set count $3
		flags $0800 ; set address bit
		literal $55 ; load value to store
		store $0    ; store in I/O register
		flags $0    ; reset address bit
	label start
		flags $2    ; borrow flag needs to be set to perform subtraction correctly.
		load  count ; load the counter variable
		add   $1    ; add 1 to count
		and   $F    ; % 15
		store count ; save result
		flags $0    ; get flags
		and   $4    ; mask off carry flag
		jumpz start ; jump back to start if non-zero

	label end
		flags $80 ; halt
	 

# To-Do

This is more of a nice-to-have list, and a list of ideas.

* Implement Memory mapped I/O in VHDL and in simulator
  - Add an I/O line, or allow the top four bits of the address to be set to
  a default value (use more flag bits?).
  - Add a timer
  - Implement a software only 9600 baud UART driver
  - Add input for switches
  - Add a bit-serial multiplier to the project, this could be made to
  be configurable so that it uses different types of multiplication
  depending on a generic parameter. The interface would need to be the
  same under all circumstances, so the package to select different
  multiplication types could have modules that provide those different
  interfaces.
* Port a simple, very cut down, Forth
* Do the program counter addition in parallel with the execution, or fetch
* Make an N-Bit version of the tool-chain, the VHDL CPU can be of an arbitrary
  width (so long as N is greater or equal to 8), but without the tool-chain to
  support that, it is kind of useless.
* Use a LFSR instead of a Program Counter? (see
  <https://news.ycombinator.com/item?id=11978900>)
* Add an interrupt request line
* A good project to use this CPU for would be to reimplement the VT100 terminal
  emulator used in <https://github.com/howerj/forth-cpu>. I could perhaps
  reimplement the core, which came from <http://www.javiervalcarce.eu/html/vhdl-vga80x40-en.html>.
  Less hardware could be used, whilst the functionality could be increased. The
  CPU takes up very little room and two of the FPGA dual-port block RAM devices 
  are already required by the VGA module - one for font (of which only a
  fraction of the memory and a single port is used) and the memory required
  for the text buffer. 
* Implement a bit-banged UART as a program. Doing this (and perhaps integrating
  this with the VGA core) would mean even fewer resources would be needed.
* Add a timer peripheral into the CPU core itself so it is always available. It
  should be capable of generating interrupts for the CPU. This could be used
  so the CPU always has a baud rate counter.

For the BCPU and its internals:
* Add interrupt handling, which will require a way of saving
the program counter somewhere. A call and return instruction
would be very useful for this, but would require more states
and a stack pointer register. Main memory could be used for
the stack.
* Allow the CPU to be customized via generics, such as:
  * Type of instructions available
* Try to merge ADVANCE into one of the other states if possible,
or at least do the PC+1 in parallel with EXECUTE.
* Allow more data/IO to be addressed by using more flag bits
* Add assertions, model/specify behaviour
  - Assert output lines are correct for the appropriate states
  and instructions.
* The 'iFLAGS' instruction could be improved; the operand
and accumulator could be used to set the new value of the flag
register whilst the accumulator is set to the flag register before
modification.

For the assembler/simulator:
- Read from a string not a file
- Allow the inclusion of other files with an 'include' directive
- Add primitive macro system
- Make the assembler smaller by rewriting it


# References / Appendix

The state-machine diagram was made using [Graphviz][], and can be viewed and
edited immediately by copying the following text into [GraphvizOnline][].

	digraph bcpu {
		reset -> fetch [label="start"]
		fetch -> execute
		fetch -> reset  [label="flag(RST) = '1'"]
		fetch -> halt  [label="flag(HLT) = '1'"]
		execute -> advance
		execute -> store   [label="op = 'store'"]
		execute -> load   [label="op = 'load'"]
		store -> advance
		load -> advance
		advance -> fetch
		halt -> halt
	}


For timing diagrams, use [Wavedrom][] with the following text:

	{signal: [
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},
	  {name: 'cmd',   wave: 'x2..................', data: ['HALT']},
	  {name: 'ie',    wave: 'x0..................'},
	  {name: 'oe',    wave: 'x0..................'},
	  {name: 'ae',    wave: 'x0..................'},
	  {name: 'o',     wave: 'x0..................'},
	  {name: 'i',     wave: 'x...................'},
	  {name: 'halt',  wave: 'x1..................'},
	  {},
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},
	  {name: 'cmd',   wave: 'x2................xx', data: ['ADVANCE']},
	  {name: 'ie',    wave: 'x0.................x'},
	  {name: 'oe',    wave: 'x0.................x'},
	  {name: 'ae',    wave: 'x01...............0x'},
	  {name: 'o',     wave: 'x0================0x', data: ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', 'F12', 'F13', 'F14', 'F15']},
	  {name: 'i',     wave: 'x.................xx'},
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},      
	  {name: 'cmd',   wave: 'x2................xx', data: ['LOAD']},
	  {name: 'ie',    wave: 'x01...............0x'},
	  {name: 'oe',    wave: 'x0.................x'},
	  {name: 'ae',    wave: 'x0.................x'},
	  {name: 'o',     wave: 'x0.................x'},
	  {name: 'i',     wave: 'x.================xx', data: ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15']},
	  {name: 'halt',  wave: 'x0.................x'},
	  {}, 
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},
	  {name: 'cmd',   wave: 'x2................xx', data: ['STORE']},
	  {name: 'ie',    wave: 'x0.................x'},
	  {name: 'oe',    wave: 'x01...............0x'},
	  {name: 'ae',    wave: 'x0.................x'},
	  {name: 'o',     wave: 'x0================0x', data: ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15']},
	  {name: 'i',     wave: 'x.................xx'},
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},
	  {name: 'cmd',   wave: 'x2................xx', data: ['EXECUTE: LOAD, STORE, JUMP, JUMPZ']},
	  {name: 'ie',    wave: 'x0.................x'},
	  {name: 'oe',    wave: 'x0.................x'},
	  {name: 'ae',    wave: 'x01...............0x'},
	  {name: 'o',     wave: 'x0================0x', data: ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', 'F12', 'F13', 'F14', 'F15']},
	  {name: 'i',     wave: 'x.................xx'},
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},      
	  {name: 'cmd',   wave: 'x2................xx', data: ['EXECUTE: NORMAL INSTRUCTION']},
	  {name: 'ie',    wave: 'x0.................x'},
	  {name: 'oe',    wave: 'x0.................x'},
	  {name: 'ae',    wave: 'x0.................x'},
	  {name: 'o',     wave: 'x0.................x'},
	  {name: 'i',     wave: 'x.................xx'},
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},
	  {name: 'cmd',   wave: 'x2................xx', data: ['FETCH']},
	  {name: 'ie',    wave: 'x01...............0x'},
	  {name: 'oe',    wave: 'x0.................x'},
	  {name: 'ae',    wave: 'x0.................x'},
	  {name: 'o',     wave: 'x0.................x'},
	  {name: 'i',     wave: 'x.================xx', data: ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15']},
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	  {name: 'clk',   wave: 'pp...p...p...p...p..'},
	  {name: 'cycle', wave: '22222222222222222222', data: ['prev', 'init','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', 'next', 'rest']},
	  {name: 'cmd',   wave: 'x2................xx', data: ['RESET']},
	  {name: 'ie',    wave: 'x0.................x'},
	  {name: 'oe',    wave: 'x01...............0x'},
	  {name: 'ae',    wave: 'x01...............0x'},
	  {name: 'o',     wave: 'x0.................x'},
	  {name: 'i',     wave: 'x.................xx'},  
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	]}



That's all folks!

[H2]: https://github.com/howerj/forth-cpu
[Soft-Counter]: https://en.wikipedia.org/wiki/Soft_microprocessor#Core_comparison
[bit-serial CPU]: https://en.wikipedia.org/wiki/Bit-serial_architecture
[VHDL]: https://en.wikipedia.org/wiki/VHDL
[GHDL]: http://ghdl.free.fr/
[Graphviz]: https://graphviz.org/
[GraphvizOnline]: https://dreampuf.github.io/GraphvizOnline
[bit.vhd]: bit.vhd
[bit.c]: bit.c
[FPGA]: https://en.wikipedia.org/wiki/Field-programmable_gate_array
[Wavedrom]: https://wavedrom.com/editor.html
[Cool ASCII Text]: http://www.patorjk.com/software/taag
[Xilinx ISE 14.7]: https://www.xilinx.com/products/design-tools/ise-design-suite/ise-webpack.html
[Nexys 3]: https://store.digilentinc.com/nexys-3-spartan-6-fpga-trainer-board-limited-time-see-nexys4-ddr/
[Spartan-6]: https://www.xilinx.com/products/silicon-devices/fpga/spartan-6.html
[bit.asm]: bit.asm
[Digilent]: https://store.digilentinc.com/

<style type="text/css">
	body{
		max-width: 50rem;
		padding: 2rem;
		margin: auto;
		line-height: 1.6;
		font-size: 1rem;
		color: #444;
	}
	h1,h2,h3 {
		line-height:1.2;
	}
	table {
		width: 100%; 
		border-collapse: collapse;
	}
	table, th, td{
		border: 0.1rem solid black;
	}
	img {
		display: block;
		margin: 0 auto;
    		margin-left: auto;
    		margin-right: auto;
	}
	code { 
		color: #091992; 
		display: block;
		margin: 0 auto;
    		margin-left: auto;
    		margin-right: auto;

	} 
</style>

