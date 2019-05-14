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
variable r0
variable r1
variable r2
variable r3
variable sp

variable count
set count $3
	literal $800 ; address bit
	flags $7FF   ; set address bit and rotate mode
	literal $2   ; load 2
	lshift $0FFF ; rotate this to high bits
	or $48       ; load value to store
	store $1     ; store in I/O register
	literal $0
	flags $7FF   ; reset address bit
label start
	load  count ; 
	add   $1    ; add 2 to count
	and   $F    ; % 15
	store count ; save result
	flags $FFF  ; get flags
	and   $4    ; mask off carry flag
	jumpz start ; jump back to start if non-zero

label end
	literal halt
	flags $7F ; halt
 
