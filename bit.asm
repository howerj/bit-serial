# A simple test program, keeping adding one to
# a variable until it is larger than $10, then halt
variable count
nop   $0
label start
load  count
add   $1
and   $F
store count
less  $1
jumpz start
halt  $0
