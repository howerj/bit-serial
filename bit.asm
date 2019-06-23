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
constant halt $80

variable count
set count $3
	literal $2   ; load 2
	lshift $0FFF ; shift this to high bits
	or $48       ; load value to store
	out   $1     ; store in I/O register
label start
	load  count ; 
	add   $1    ; add 1 to count
	and   $F    ; % 15
	store count ; save result
	flags $FFF  ; get flags
	and   $2    ; mask off zero flag
	jumpz start ; jump back to start if non-zero

label end
	literal halt
	flags $7F ; halt
 
