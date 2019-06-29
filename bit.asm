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
.constant fCy  $1
.constant fZ   $2
.constant fNg  $4
.constant fPar $8
.constant fRot $10
.constant fR   $20
.constant fInd $40
.constant fHlt $80

; variables start from the end of memory and go down
.variable irq
.variable allset
.variable r0
.variable r1
.variable r2
.variable r3
.variable saved-flags
.variable sp
.variable rp

.set allset $FFFF

.macro flags
	set $1
.end

.macro flags?
	get $1
.end

.macro halt
	literal fHlt
	flags
.end

.macro indirect
	literal fInd
	flags
.end

.macro invert
	store r0
	flags?
	store saved-flags
	literal fInd
	flags
	load r0
	xor allset
	load saved-flags
	flags
.end

; works if indirect is set or not if address zero is zero
.macro nop
	or $0
.end

.macro clr
	literal $0
.end

; works if indirect is set or not if address one is one
.macro inc
	add $1
.end

.label entry
	$0           ; all zeros, must be first instruction for 'nop'
	$1           ; '1', must be second instruction for 'inc' to work
	clr          ; clear accumulator
	flags        ; clear all flags

	literal $2   ; load 2
	lshift $0FFF ; shift this to high bits
	or     $48   ; load value to store
	out    $1    ; store in I/O register
.label start

.variable count
.set count $3
	load  count
	add   $1    ; add 1 to count
	and   $F    ; % 15
	store count ; save result
	flags?
	and   fZ    ; mask off zero flag
	jumpz start ; jump back to start if non-zero

.label end
	halt
 
