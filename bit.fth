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
: $literal [char] " word count dup tc, 0 ?do count tc, loop drop talign ;
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
\ ( 
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
	halt )

\ TODO: Implement a virtual machine for a token thread stack machine, see
\ <https://en.wikipedia.org/wiki/Threaded_code#Token_threading> for more
\ information. It is this machine that we will target. We will have to put
\ all the words we have defined here into the assembly word-set and define
\ an entirely new of words. We will want to keep this virtual machine as
\ compact as possible, perhaps under 512 bytes, including return and program
\ stacks! That might be a bit of a stretch however.

\ Memory locations 0 and 1 should contain 0 and 1 respectively.
$200 tvar ip  \ entry point of virtual machine program
$200 tvar sp  \ stack pointer
$180 tvar rp  \ return stack pointer
0 tvar w      \ working pointer
0 tvar tos    \ top of stack
0 tvar t      \ temporary register
FFFF tvar set \ all bits set
FF tvar half  \ lowest set

: fdefault flgInd iLITERAL flags! ;
\ : opcode: there . label: ; 
: opcode: create there dup . , does> @ , ;
: vcell 1 ;
: -vcell set ;
: pc! 0 iSET ; ( acc -> pc )
: --sp sp iLOAD-C  vcell iADD sp iSTORE-C ;
: ++sp sp iLOAD-C -vcell iADD sp iSTORE-C fdefault ;
: --rp rp iLOAD-C -vcell iADD rp iSTORE-C fdefault ;
: ++rp rp iLOAD-C  vcell iADD rp iSTORE-C ;	


label: start
	$200 iLITERAL
	ip iSTORE-C
label: next
	fdefault
	\ *ip++ -> w
	ip iLOAD
	w iSTORE-C
	ip iLOAD-C
	vcell iADD
	ip iSTORE-C
	\ jump **w++
	w iLOAD-C
	t iSTORE-C
	vcell iADD
	w iSTORE-C
	t iLOAD
	t iSTORE-C
	t iLOAD
	pc!
	
label: nest
	\ ip -> *rp++
	ip iLOAD-C
	rp iSTORE
	rp iLOAD-C
	vcell iADD
	rp iSTORE-C
	\ w -> ip
	w iLOAD-C
	ip iSTORE-C
	next iJUMP
label: unnest
	\ *--rp -> ip
	rp iLOAD-C
	-vcell iADD
	rp iSTORE-C
	fdefault
	rp iLOAD
	ip iSTORE-C
	next iJUMP
label: skip
	\ jump *(*++ip)
	ip iLOAD-C
	vcell iADD
	ip iSTORE-C
	ip iLOAD
	pc!
label: opPush
	++sp
	tos iLOAD-C
	sp iSTORE
	
	ip iLOAD-C
	vcell iADD
	t iSTORE-C
	t iLOAD
	
	tos iSTORE-C
	skip iJUMP
label: opJump
	ip iLOAD-C vcell iADD ip iSTORE-C
	ip iLOAD
	pc!
label: opJumpZ
	tos iLOAD-C
	t iSTORE-C
	--sp
	sp iLOAD
	tos iSTORE
	t iLOAD-C
	opJump iJUMPZ
	ip iLOAD-C vcell iADD ip iSTORE-C
	skip iJUMP
label: opHalt
	halt
label: opBye
	reset
label: opAnd
	sp iLOAD
	tos iAND
	tos iSTORE-C
	--sp
	skip iJUMP
label: opOr
	sp iLOAD
	tos iOR
	tos iSTORE-C
	--sp
	skip iJUMP
label: opXor
	sp iLOAD
	tos iOR
	tos iSTORE-C
	--sp
	skip iJUMP
label: opInvert
	tos iLOAD-C
	set iXOR
	tos iSTORE-C
	skip iJUMP
label: opAdd
	sp iLOAD
	tos iADD
	tos iSTORE-C
	fdefault
	--sp
	skip iJUMP
label: opLOAD
	tos iLOAD
	skip iJUMP
label: opSTORE
	sp iLOAD
	tos iSTORE
	--sp
	sp iLOAD
	tos iSTORE-C
	--sp
	skip iJUMP
\ Also need >r r> r@ r sp lshift rshift 1+ 1-

label: i_program
	opHalt t,

$200 tdp !
	i_program t,



: lit opPush t, t, ;


\ TODO: Redefine -- if, else, then, begin, until, ... in a new vocabulary
\ 200 tdp !
\	opHalt

save-hex bit.hex

only forth definitions decimal
bye
