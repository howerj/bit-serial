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
set count $3

	flags $0
	clr
label start
	flags $2    ; borrow flag needs to be set to perform subtraction correctly.
	load  count ; 
	add   $1    ; add 2 to count
	and   $F    ; % 15
	store count ; save result
	flags $0    ; get flags
	and   $4    ; mask off carry flag
	jumpz start ; jump back to start if non-zero

label end
	flags $80 ; halt
 
