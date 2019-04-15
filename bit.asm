# TODO:
# - Make some self-modifying code so a call stack can be setup
#   - Implement assembly functions for subtraction, push, pop,
#   call, return, more than, equality, etcetera.
# - Make a small virtual machine for a thread code interpreter
# - Implement a cut-down Forth, or a simple command interpreter
# of some kind.
#
# FORTH PLAN
#
# The plan is to implement a tiny Forth. First a threaded code
# interpreter would have to be built, then a few primitive Forth
# words. 
#
# The following Forth words should be implemented:
#
#	: ; create does> + - lshift rshift and or xor invert
#	word parse count if else then begin until immediate
#	! @ exit >r r> r@ dup swap over drop . , here ( key?
#	emit
#
# What is implement should be as standards compliant as possible
# without making the interpreter too big. A few other words may
# be added because they are necessary to implement others words
# in the desired, minimal, word list. 
#
# There is only 4096 Words (8KiB) to work with, and squeezing
# a Forth into that might be quite difficult. This must include
# the simulated stacks, and scratch space and variables needed
# by the system.
#
# See:
# - https://en.wikipedia.org/wiki/Threaded_code
# - https://github.com/howerj/embed
#

# A simple test program, keeping adding one to
# a variable until it is larger than $10, then halt
allocate $20
allocate $20
variable rp
variable sp
variable count
literal $fff
store   rp
literal $fc0
store   sp
# Testing forward references
jump  end
label start
load  count
add   $1
and   $F
store count
less  $1
jumpz start
halt  $1
# and jump back...
label end
jump  start


