( Cross Compiler for the bit-serial CPU available at
  <https://github.com/howerj/bit-serial>

  Based off of the meta-compiler for the j1 processor available at
  <https://github.com/samawati/j1eforth> )

only forth definitions hex

wordlist constant meta

: (order) ( w wid*n n -- wid*n w n )
   dup if
    1- swap >r recurse over r@ xor if
     1+ r> -rot exit then r> drop then ;
: -order ( wid -- ) get-order (order) nip set-order ;
: +order ( wid -- ) dup >r -order get-order r> swap 1+ set-order ;

get-current meta set-current drop
meta +order

000a constant =lf
   2 constant =cell
2000 constant size

create tflash size cells here over erase allot

variable tdp
variable tep
size =cell - tep !

: there tdp @ ;
: tend tep @ ;
: tc! tflash + c! ;
: tc@ tflash + c@ ;
: t! over ff and over tc! swap 8 rshift swap 1+ tc! ;
: t@ dup tc@ swap 1+ tc@ 8 lshift or ;
: talign there 1 and tdp +! ;
: tc, there tc! 1 tdp +! ;
: t, there t! 2 tdp +! ;
: $literal [char] " word count dup tc, 0 ?do
	count tc, loop drop talign ;
: tallot tdp +! ;
: org tdp ! ;

: hex# ( u -- addr len )  0 <# base @ >r hex =lf hold # # # # r> base ! #> ;
: save-hex ( <name> -- )
  parse-word w/o create-file throw
  size 0 do i t@  over >r hex# r> write-file throw 2 +loop
   close-file throw ;

: tvar tend t! create tend , -2 tep +! does> @ ;
: tcnst tend t! create tend @ , -2 tep +! does> @ ;
: label: create there , does> @ ;

: iOR      0000 or t, ;
: iAND     1000 or t, ;
: iXOR     2000 or t, ;
: iADD     3000 or t, ;
: iLSHIFT  4000 or t, ;
: iRSHIFT  5000 or t, ;
: iLOAD    2/ 6000 or t, ;
: iSTORE   2/ 7000 or t, ;

: iLOAD-C  2/ 8000 or t, ;
: iSTORE-C 2/ 9000 or t, ;
: iLITERAL A000 or t, ;
: iUNUSED  B000 or t, ;
: iJUMP    C000 or t, ;
: iJUMPZ   D000 or t, ;
: iSET     E000 or t, ;
: iGET     F000 or t, ;

 1 constant flgCy
 2 constant flgZ
 4 constant flgNg
 8 constant flgPar
10 constant flgRot
20 constant flgR
40 constant flgInd
80 constant flgHlt

0 tvar cnt
000F tvar nib0
2048 tvar uartWrite
2000 tvar _uwrite

: flags? 1 iGET ;
: flags! 1 iSET ;
: clr 0 iLITERAL ;
: halt flgHlt iLITERAL flags! ;
: reset flgR   iLITERAL flags! ;
: indirect flgInd iLITERAL flags! ;
: direct clr flags! ;
: inc 1 iADD ;  ( works in direct/indirect mode if address[1] = 1 )
: nop 0 iOR ;   ( works in direct/indirect mode if address[0] = 0 )
: branch 2/ iJUMP ;
: ?branch 2/ iJUMPZ ;
: zero? flags? 2 iAND ;

: begin there ;
: until ?branch ;

: if there 0 ?branch ;
: skip there 0 branch ;
: then begin 2/ over t@ or swap t! ;
: else skip swap then ;
: while if swap ;
: repeat branch then ;
: again branch ;

0 tvar _emit ( TODO: wait if TX Queue full )
: emit _emit iSTORE-C _uwrite iLOAD-C _emit 2/ iOR 801 iSET ; 

label: entry
	0 t,
	1 t,
	2 t,
	clr
	indirect \ We assume indirect is on for all instructions
	$800 iGET
	$800 iSET

	char H iLITERAL emit 

	clr
	begin
		cnt iLOAD-C
		inc
		nib0 2/ iAND
		cnt iSTORE-C
		zero?
	until

label: end
	\ reset
	halt

\ TODO: Implement a virtual machine for a token thread stack machine, see
\ <https://en.wikipedia.org/wiki/Threaded_code#Token_threading> for more
\ information. It is this machine that we will target. We will have to put
\ all the words we have defined here into the assembly word-set and define
\ an entirely new of words. We will want to keep this virtual machine as
\ compact as possible, perhaps under 512 bytes, including return and program
\ stacks! That might be a bit of a stretch however.

\ Memory locations 0 and 1 should contain 0 and 1 respectively.
$200 tvar vpc \ entry point of virtual machine program
$200 tvar sp  \ stack pointer
$180 tvar rp  \ return stack pointer
0 tvar r0     \ working pointer
0 tvar tos    \ top of stack
0 tvar rtos   \ top of return stack
FFFF tvar set \ all bits set
FF tvar half

: fdefault flgInd iLITERAL flags! ;
: spush sp iLOAD-C set iADD fdefault sp iSTORE-C tos iLOAD-C sp iSTORE ;
: spop sp iLOAD-C 1 iADD sp iSTORE-C sp iLOAD tos iSTORE-C ;
\ TODO return stack needs to grow upwards...
: rpush rp iLOAD-C set iADD fdefault rp iSTORE-C rtos iLOAD-C rp iSTORE ;
: rpop rp iLOAD-C 1 iADD rp iSTORE-C rp iLOAD rtos iSTORE-C ;
: opcode: there . label: ; \ TODO: Assert opcode address <256

\ TODO: Fix vpc load/stores so they operate on bytes!
label: start
	$200 iLITERAL
	vpc iSTORE-C
label: vm
	fdefault
	vpc iLOAD-C
	r0 iSTORE-C
	1 iADD
	vpc iSTORE-C
	r0 iLOAD-C 1 iAND if
		r0 iLOAD
		half iRSHIFT	
	else
		r0 iLOAD
		half iAND
	then
	\ TODO Add offset into thread/Or shift left
	0 iSET

: next vm iJUMP ; \ TODO 2/?

opcode: opPushByte \ Op8
	spush vpc iLOAD tos iSTORE-C
	vpc iLOAD-C 1 iADD vpc iSTORE-C
	next
opcode: opPushWord \ Op16
	spush vpc iLOAD tos iSTORE-C
	vpc iLOAD-C 2 iADD
	next
opcode: opReturn
	rtos iLOAD-C r0 iSTORE-C rpop 0 iSET
opcode: opCall     \ Op16
	rpush 0 iGET rtos iSTORE-C
	vpc iLOAD
	0 iSET
opcode: opJump     \ Op16
	vpc iLOAD
	0 iSET
opcode: opJumpZero \ Op16
	tos iLOAD-C r0 iSTORE-C spop
	r0 iLOAD-C if vpc iLOAD 0 iSET then 
	next
opcode: opAdd
	tos iLOAD-C r0 iSTORE-C spop
	r0 iADD tos iSTORE-C
	next
opcode: opAddWithCarry
	tos iLOAD-C r0 iLOAD-C spop
	r0 iADD tos iSTORE-C spush
	next
opcode: opSubtract
	tos iLOAD-C r0 iSTORE-C spop
	set iXOR 1 iADD  tos iSTORE-C
	next
opcode: opOr
	tos iLOAD-C r0 iSTORE-C spop
	r0 iOR tos iSTORE-C
	next
opcode: opXor
	tos iLOAD-C r0 iSTORE-C spop
	r0 iXOR tos iSTORE-C
	next
opcode: opAnd
	tos iLOAD-C r0 iSTORE-C spop
	r0 iAND tos iSTORE-C
	next
opcode: opInvert
	tos iLOAD-C set iXOR tos iSTORE-C
	next
opcode: opLshift
	tos iLOAD-C r0 iSTORE-C spop
	r0 iLSHIFT tos iSTORE-C
	next
opcode: opRshift
	tos iLOAD-C r0 iSTORE-C spop
	r0 iRSHIFT tos iSTORE-C
	next
opcode: opLoad
	tos iLOAD tos iSTORE-C
	next
opcode: opStore
	tos iLOAD-C r0 iSTORE-C spop
	next
opcode: opHalt
	halt
opcode: opReset
	reset

save-hex bit.hex

only forth definitions decimal
bye
