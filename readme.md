# readme.md
# A Bit-Serial CPU (written in VHDL) and a simulator

| Project   | Bit-Serial CPU in VHDL                 |
| --------- | -------------------------------------- |
| Author    | Richard James Howe                     |
| Copyright | 2017-2018 Richard James Howe           |
| License   | MIT                                    |
| Email     | howe.r.j.89@gmail.com                  |
| Website   | <https://github.com/howerj/bit-serial> |

## Introduction

This is a project for a bit-serial CPU, which is a CPU that has an architecture
which processes a single bit at a time instead of in parallel like a normal
CPU. This allows the CPU itself to be a lot smaller, the penalty is that it is
a lot slower.

## To-Do

* Make the instruction set denser
  - Turn halt into a CPU set/get instruction
  - Merge left/right shift into a single instruction?
  - Fully populate instruction set
* Implement Memory mapped I/O in VHDL and in simulator
* Fill up instruction set (which instructions arithmetic instructions are optimal/easy to implement?)
* Implement in VHDL (along with a bit-parallel alternative - use the parallel
  version to test the equivalence with the bit-serial version)
* Document system (instruction set tables, and state machine diagrams, cycle timing)
* Make an assembler
* Port a simple, very cut down, Forth

## References

See:

* <https://en.wikipedia.org/wiki/Bit-serial_architecture>
* <https://en.wikipedia.org/wiki/Serial_computer>
* For diagrams: <https://dreampuf.github.io/GraphvizOnline>

<style type="text/css">body{margin:40px auto;max-width:850px;line-height:1.6;font-size:16px;color:#444;padding:0 10px}h1,h2,h3{line-height:1.2}table {width: 100%; border-collapse: collapse;}table, th, td{border: 1px solid black;}code { color: #091992; } </style>
