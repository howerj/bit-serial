# BIT SERIAL CPU and TOOL-CHAIN

*  Project:   Bit-Serial CPU in VHDL
*  Author:    Richard James Howe
*  Copyright: 2019,2020 Richard James Howe
*  License:   MIT
*  Email:     howe.r.j.89@gmail.com
*  Website:   <https://github.com/howerj/bit-serial>

*Processing data one bit at a time, since 2019*.

# Introduction

This is a project for a [bit-serial CPU][], which is a CPU that has an architecture
which processes a single bit at a time instead of in parallel like a normal
CPU. This allows the CPU itself to be a lot smaller, the penalty is that it is
*a lot* slower. The CPU itself is called *bcpu*.

The CPU is incredibly basic, lacking features required to support
higher level programming (such as function calls). Instead such features can 
be emulated if they are needed. If such features are needed, or faster
throughput (whilst still remaining quite small) other [Soft-Core][] CPUs are
available, such as the [H2][]. 

To build and run the C based simulator for the project, you will need a C
compiler and 'make'. To build and run the [VHDL][] simulator, you will need [GHDL][]
installed.

The cross compiler requires [gforth][].

The target [FPGA][] that the system is built for is a [Spartan-6][], for a
[Nexys 3][] development board. [Xilinx ISE 14.7][] was used to build the
project.

The following 'make' targets are available:

	make

By default the [VHDL][] test bench is built and simulated in [GHDL][]. This
requires [gforth][] to assemble the test program [bit.fth][] into a file 
readable by the simulator.

	make run

This target builds the C based simulator, assembles the test program
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

# Use Case

Often in an [FPGA][] design there is spare Dual Port Block RAM (BRAM) available,
either because only part of the BRAM module is being used or because it is not
needed entirely. Adding a new CPU however is a bigger decision than using spare
BRAM capacity, it can take up quite a lot of floor space, and perhaps other
precious resources. If this is the case then adding this CPU costs practically
nothing in terms of floor space, the main cost will be in development time.

In short, the project may be useful if:

* FPGA Floor space is at a premium in your design.
* You have spare memory for the program and storage.
* You need a programmable CPU that supports a reasonable instruction set.
* *Execution speed is not a concern*.

# CPU Specification

The CPU is a 16-bit design, in principle a normal bit parallel CPU design could
be implemented of the same CPU, but in practice you not end up with a CPU like 
this one if you remove the bit-serial restriction. 

The CPU has 16 operation, each instruction consists of a 4-bit operation field
and a 12-bit operand. Depending on the CPU mode that operand and instruction
that operand can either be a literal or an address to load a 16-bit word from
(addresses are word and not byte oriented, so the lowest bit of an address
specifies the next word not byte). Only the first 8 operations can have their
operand indirected, which is deliberate.

The CPU is an accumulator machine, all instructions either modify or use the
accumulator to store operation results in them. The CPU has three registers
including the accumulator, the other two are the program counter which is
automatically incremented after each instruction excluding the jump
instructions (the SET instruction is also excluded when setting the program
counter only) and a flags register.

The instructions are:

	| ----------- | -------------------------------------- | --------------------------------- | ---------------- |
	| Instruction | C Operation                            | Description                       | Cycles           |
	| ----------- | -------------------------------------- | --------------------------------- | ---------------- |
	| OR          | acc |= lop                             | Bitwise Or                        | [3 or 5]*(N+1)   |
	| AND         | acc &= indir ? lop : 0xF000 | lop      | Bitwise And                       | [3 or 5]*(N+1)   |
	| XOR         | acc ^= lop                             | Bitwise Exclusive Or              | [3 or 5]*(N+1)   |
	| ADD         | acc += lop + carry;                    | Add with carry, sets carry        | [3 or 5]*(N+1)   |
	| LSHIFT      | acc = acc << lop (or rotate left)      | Shift left or Rotate left         | [3 or 5]*(N+1)   |
	| RSHIFT      | acc = acc >> lop (or rotate right)     | Shift right or Rotate right       | [3 or 5]*(N+1)   |
	| LOAD        | acc = memory(lop)                      | Load                              | [4 or 6]*(N+1)   |
	| STORE       | memory(lop) = acc                      | Store                             | [4 or 6]*(N+1)   |
	| LOADC       | acc = memory(op)                       | Load from memory constant addr    | 4*(N+1)          |
	| STOREC      | memory(op) = acc                       | Store to memory constant addr     | 4*(N+1)          |
	| LITERAL     | acc = op                               | Load literal into accumulator     | 3*(N+1)          |
	| UNUSED      | N/A                                    | Unused instruction                | 3*(N+1)          |
	| JUMP        | pc = op                                | Unconditional Jump                | 2*(N+1)          |
	| JUMPZ       | if(!acc){pc = op }                     | Jump If Zero                      | [2 or 3]*(N+1)   |
	| SET         | if(op&0x800) { io(op|0x8000) = acc   } | Set I/O or Register               | [3 or 4]*(N+1)   |
	|             | else { if(op&1){flg=acc}else{pc=acc} } |                                   |                  |
	| GET         | if(op&0x800) { acc = io(op|0x8000)   } | Get I/O or Register               | [3 or 4]*(N+1)   |
	|             | else { if(op&1){acc=flg}else{acc=pc} } |                                   |                  |
	| ----------- | -------------------------------------- | --------------------------------- | ---------------- |

* pc    = program counter
* acc   = accumulator
* indir = indirect flag
* lop   = instruction operand if indirect flag not set, otherwise it equals to the memory
          location pointed to by the operand
* op    = instruction operand
* flg   = flags register
* N     = bit width, which is 16.

The GET/SET instructions can be used to perform I/O, and is also used to get/set
some of the registers (program counter and flag register). These are the most
complicated instructions.

Notice that the when the indirect flag is *not* set that the top bits will be
anded with '0xF' and not '0x0'.

The number of cycles an instruction takes to complete depends on whether it
performs an indirection, or in the case of GET/SET it depends if it it setting
the program counter (2 cycles only) or the flags register (3 cycles), or performing 
an I/O operation (4 cycles), getting the flags or program counter always costs
3 cycles.

The flags in the 'flg' register are:

	| ---- | --- | --------------------------------------- |
	| Flag | Bit | Description                             |
	| ---- | --- | --------------------------------------- |
	| Cy   |  0  | Carry flag, set by addition instruction |
	| Z    |  1  | Zero flag                               |
	| Ng   |  2  | Negative flag                           | 
	| PAR  |  3  | Parity flag, parity of accumulator      |
	| ROT  |  4  | If set, shifts become rotates           |
	| R    |  5  | Reset Flag - Resets the CPU             |
	| IND  |  6  | Indirect Flag - turns indirection on    |
	| HLT  |  7  | Halt Flag - Stops the CPU               |
	| ---- | --- | --------------------------------------- |

* The carry flag (Cy) is set by the ADD instruction, it can also be set and cleared
with the GET/SET instructions.
* 'Z' is set whenever the accumulator is zero.
* 'Ng' is set whenever the accumulator has its highest bit set, indicating that
  the accumulator is negative.
* 'PAR' is the parity of the accumulator, the parity flag can be compiled at 
synthesis time to even or odd parity.
* 'ROT', if set, means the 'LSHIFT' and 'RSHIFT' instructions will perform
rotations instead of left/right shifts.
* 'R', Reset flag, this resets the CPU immediately, only the HLT flag takes
precedence.
* 'IND', The indirect flag, which enables indirection on those instructions
which can be indirected.
* 'HLT', The halt flag takes priority over everything else, sending the CPU
into a halt state.

There is really not much else to this CPU from the point of view of a user of
this core, integrating this core into another system is more complicated
however, you will need to be far more aware of timing of signals and their
enable lines. Much like the processor, a single bit bus in conjunction with an
enable is used to communicate with the outside world.

The internal state of the CPU is minimal, to make a working system the memory
and I/O controller will need (shift) registers to store the address and 
input/output.

# Peripherals

The system has a minimal set of peripherals; a bank of switches with LEDs next
to each switch and a UART capable of transmission and reception, other
peripherals could be added as needed. 

## Register Map

The I/O register map for the device is very small as there are very few
peripherals. Note that the addresses are of the form '0x88XX', this is the
address seen on the address bus, you only need to write to the address '0x08XX'
using the GET/SET instructions, which will set the top bit automatically. This
is done so that the LOAD/STORE instructions can use the full range of their
operand for memory operations.

	| ------- | -------------- |
	| Address | Name           |
	| ------- | -------------- |
	| 0x8800  | LED/Switches   |
	| 0x8801  | UART TX/RX     |
	| 0x8802  | UART Clock TX  |
	| 0x8803  | UART Clock RX  |
	| 0x8804  | UART Control   |
	| ------- | -------------- |

* LED/Switches

A bank of switches, non-debounced, with LED lights next to them.

	+---------------------------------------------------------------+
	| F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
	+---------------------------------------------------------------+
	|                           |   Switches 1 = on, 0 = off        | READ
	+---------------------------------------------------------------+
	|                           |   LED 1 = on, 0 = off             | WRITE
	+---------------------------------------------------------------+

* UART TX/RX

The UART TX/RX register is used to read and write data bytes to the UART and
check on the UART status. The UART has a FIFO that is used to capture the
results of the UART. The usage of which is non-optional.

	+---------------------------------------------------------------+
	| F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
	+---------------------------------------------------------------+
	|       |TFF|TFE|   |RFF|RFE|      RX DATA BYTE                 | READ
	+---------------------------------------------------------------+
	|   |TFW|       |RFR|       |      TX DATA BYTE                 | WRITE
	+---------------------------------------------------------------+
	RFE = RX FIFO EMPTY
	RFF = RX FIFO FULL
	RFR = RX FIFO READ ENABLE
	TFE = TX FIFO EMPTY
	TFF = TX FIFO FULL
	TFW = TX FIFO WRITE ENABLE

* UART Clock TX

The UART Transmission clock, independent from the Reception Clock, is
controllable via this register.

Defaults are: 115200 Baud

	+---------------------------------------------------------------+
	| F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
	+---------------------------------------------------------------+
	|                                                               | READ
	+---------------------------------------------------------------+
	|             UART TX CLOCK DIVISOR                             | WRITE
	+---------------------------------------------------------------+

* UART Clock RX

The UART Reception clock, independent from the Transmission Clock, is
controllable via this register.

Defaults are: 115200 Baud

	+---------------------------------------------------------------+
	| F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
	+---------------------------------------------------------------+
	|                                                               | READ
	+---------------------------------------------------------------+
	|            UART RX CLOCK DIVISOR                              | WRITE
	+---------------------------------------------------------------+

* UART Clock Control

This clock is used to control UART options such as the number of bits, 

Defaults are: 8N1, no parity

	+---------------------------------------------------------------+
	| F | E | D | C | B | A | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
	+---------------------------------------------------------------+
	|                                                               | READ
	+---------------------------------------------------------------+
	|                               |   DATA BITS   |STPBITS|EPA|UPA| WRITE
	+---------------------------------------------------------------+
	UPA       = USE PARITY BITS
	EPA       = EVEN PARITY
	STPBITS   = Number of stop bits
	DATA BITS = Number of data bits 


# Other Soft Microprocessors

This is a *very* specialized core, that cannot be emphasized enough. It
executes slowly, but is small. Other, larger core (but still relatively small)
may be useful for your needs. In terms of engineering trade offs this design
takes things to the extreme in one direction only.

The core should be written to be portable to different [FPGA][]s, however the
author only tests what they have available (Xilinx, Spartan-6).

## The H2

Another small core, based on the J1. This core executes quite quickly and uses
few resources, although much more than this core. The instruction set is quite
dense and allows for higher level programming than just using straight
assembler.

* <https://github.com/howerj/forth-cpu>

# Project Goals

* [x] Map out a viable instruction set
* [x] Make a toolchain for the system
* [x] Make a simulator for the system
* [x] Implement the system on an FPGA
  * [x] Implement the CPU
  * [x] Implement a memory and peripheral interface
  * [ ] Add an interrupt request mechanism?
  * [ ] Add a counter/timer peripheral
  * [ ] ...that can cause an interrupt to the core
* [x] Create a tiny test program
* [x] Verify program works in hardware
* [ ] Implement a tiny Forth on the CPU
* [ ] Use in other VHDL projects
  * [ ] As a low speed UART (Bit-Banged)
  * [ ] As a VT100 interface for a VGA Text Terminal in a CGA graphics card
* [ ] Simplify the CPU

# Notes

* The CPU is difficult to program, there are three ways of remedying this;
  a complete CPU instruction set redesign, borrowing one more bit from the
  address/operand and using this as an indirection bit (which would free up
  some instructions) and the last, most preferable, is to design a tool-chain
  which hides all this by providing a Forth interpreter as a programming
  interface. The reason the processor is difficult to program for is; a lack
  of a built in call/return mechanism and instructions that require setting
  mode flags.
* Ideas for a completely different CPU architecture that is also bit serial
  include; a nibble or byte oriented CPU (with 8 or 16 bit operands), the
  former would allow for particularly dense code, potentially, or implementing
  a full stack machine instead of an accumulator machine. Stack machines are
  much easier to use and to compile to.
* Two of these cores could be hooked up to one Dual Port block RAM. This is
  another intention and goal of the device, this allows one FPGA based
  application (say a text terminal) to share memory with one BCPU core.
* A bit-parallel (or...a normal) version of this CPU could be made if software
  compatibility is desired but the design proves to be too slow, this would of
  course be bigger, and some instructions may be difficult to implement (the
  shift/rotates).
* Variable cycle states should have been used, FETCH could be 4/5 cycles,
  INDIRECT could be 12/13 cycles, OPERAND could be merged with EXECUTE, and 
  EXECUTE 16/17 along with the other instructions.
* The CPU could be simplified further if we are willing to use self-modifying
  code.
* In principle interrupts could be added in the following way:
  - During any cycle an interrupt is noted and latched in.
  - When the processor gets back into the FETCH state it checks if
  interrupts are enabled, if they are then current program counter would
  need to be exchanged with a fixed memory location (say 0xFFF), if the
  JUMP instruction was changed to be the opcode 0xF, then the current
  opcode could be replaced with all ones. A STORE of the current PC to
  0xFFF would also need to be arranged.
  - As an added extra, you could configure the processor to wake up
  out of the halt state in the event of an interrupt if interrupts are
  enabled. Alternatively, this could be the only interrupt mechanism
  allowed, which would be trivial to add.

# References / Appendix

The state-machine diagram was made using [Graphviz][], and can be viewed and
edited immediately by copying the following text into [GraphvizOnline][].


	digraph bcpu {
		reset -> fetch [label="start"]
		fetch -> execute
		fetch -> indirect [label="flag(IND) = '1'\n and op < 8"]
		fetch -> reset  [label="flag(RST) = '1'"]
		fetch -> halt  [label="flag(HLT) = '1'"]
		indirect -> operand 
		operand -> execute
		execute -> advance
		execute -> store   [label="op = 'store'"]
		execute -> load   [label="op = 'load'"]
		execute -> fetch [label="(op = 'jumpz' and acc = 0)\n or op ='jump'"]
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
	  {name: 'cmd',   wave: 'x2................xx', data: ['OPERAND or LOAD']},
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
	  {name: 'cmd',   wave: 'x2................xx', data: ['INDIRECT or EXECUTE: LOAD, STORE, JUMP, JUMPZ']},
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
	  {name: 'oe',    wave: 'x0.................x'},
	  {name: 'ae',    wave: 'x01...............0x'},
	  {name: 'o',     wave: 'x0.................x'},
	  {name: 'i',     wave: 'x.................xx'},  
	  {name: 'halt',  wave: 'x0.................x'},
	  {},
	  
	]}


That's all folks!

[gforth]: https://www.gnu.org/software/gforth/
[H2]: https://github.com/howerj/forth-cpu
[Soft-Core]: https://en.wikipedia.org/wiki/Soft_microprocessor#Core_comparison
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
[bit.fth]: bit.fth
[Digilent]: https://store.digilentinc.com/
[r8086.zip]: r8086.zip
[C]: https://en.wikipedia.org/wiki/C_%28programming_language%29

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

