# TODO:
# - Make some self-modifying code so a call stack can be setup
#   - Implement assembly functions for subtraction, push, pop,
#   call, return, more than, equality, etcetera.
# - Make a small virtual machine for a thread code interpreter
# - Implement a cut-down Forth, or a simple command interpreter
# of some kind.
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
