#!./bit -ar

; TODO:
; - Make some self-modifying code so a call stack can be setup
;   - Implement assembly functions for subtraction, push, pop,
;   call, return, more than, equality, etcetera.
; - Make a small virtual machine for a thread code interpreter
; - Implement a cut-down Forth, or a simple command interpreter
; of some kind.

; A simple test program, keeping adding one to
; a variable until it is larger than $10, then halt
variable count

label start
	load  count
	add   $1
	and   $F
	store count
	flags $0
	and   $4
	jumpz start

label end
	flags $10 ; halt
 
; ; Using sub
; label start
; load count
; add $1
; store count
; sub $F
; flags $0
; jumpz end
; jump start
; 
; label end
; flags $10 ; halt
