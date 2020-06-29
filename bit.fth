( 

Cross Compiler for the bit-serial CPU available at:

  <https://github.com/howerj/bit-serial> 


This implements a Direct Threaded Code virtual machine on which we can
build a Forth interpreter.

References:

- <https://en.wikipedia.org/wiki/Threaded_code>
- <https://github.com/samawati/j1eforth> 
- <https://github.com/howerj/embed> 
- <https://github.com/howerj/forth-cpu>

)

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
  40 constant =stksz

create tflash size cells here over erase allot

variable tdp
variable tep
size =cell - tep !

: there tdp @ ;
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
  there 0 do i t@  over >r hex# r> write-file throw =cell +loop
   close-file throw ;

: tvar create there , t, does> @ ;
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

: flags? 1 iGET ;
: flags! 1 iSET ;
: clr 0 iLITERAL ;
: halt flgHlt iLITERAL flags! ;
: reset flgR   iLITERAL flags! ;
: inc 1 iADD ;  ( works in direct/indirect mode if address[1] = 1 )
: nop 0 iOR ;   ( works in direct/indirect mode if address[0] = 0 )
: branch 2/ iJUMP ;
: ?branch 2/ iJUMPZ ;
: zero? flags? 2 iAND ;

\ : begin there ;
\ : until ?branch ;
\ : if there 0 ?branch ;
\ : skip there 0 branch ;
\ : then begin 2/ over t@ or swap t! ;
\ : else skip swap then ;
\ : while if swap ;
\ : repeat branch then ;
\ : again branch ;


0 t,  \ must be 0 ('0 iOR'  works in either indirect or direct mode)
1 t,  \ must be 1 ('1 iADD' works in either indirect or direct mode)
label: entry
0 t,  \ our actual entry point

FFFF tvar set \ all bits set, -1
0 tvar <cold> \ entry point of virtual machine program, set later on
0 tvar ip     \ instruction pointer
0 tvar w      \ working pointer
0 tvar t      \ temporary register
0 tvar tos    \ top of stack
label: RSTACK \ Return stack start, grows upwards
=stksz tallot
label: VSTACK \ Variable stack *end*, grows downwards
=stksz tallot
VSTACK =stksz + 2/ tvar sp  \ variable stack pointer
RSTACK          2/ tvar rp  \ return stack pointer

: fdefault flgInd iLITERAL flags! ;
\ : t: create there dup . , does> @ , ;
\ : ;t ;
: vcell 1 ( cell '1' should contain '1' ) ;
: -vcell set 2/ ;
: pc! 0 iSET ; ( acc -> pc )
: --sp sp iLOAD-C  vcell iADD sp iSTORE-C ;
: ++sp sp iLOAD-C -vcell iADD sp iSTORE-C fdefault ;
: --rp rp iLOAD-C -vcell iADD rp iSTORE-C fdefault ;
: ++rp rp iLOAD-C  vcell iADD rp iSTORE-C ;	

label: start
	start 2/ C000 or entry t!
	fdefault

	<cold> iLOAD-C
	ip iSTORE-C
label: next
	fdefault
	ip iLOAD-C
	w iSTORE-C
	ip iLOAD-C
	vcell iADD
	ip iSTORE-C
	w iLOAD-C pc!

( label: nest \ Must set accumulator before using '0 iGET'
	w iSTORE-C
	++rp
	w iLOAD-C
	rp iSTORE
	next branch
label: unnest
	next branch )

label: opPush
	++sp
	tos iLOAD-C
	sp iSTORE
	
	ip iLOAD-C
	w iSTORE-C
	w iLOAD
	tos iSTORE-C
	ip iLOAD-C
	vcell iADD
	ip iSTORE-C
	next branch
label: opJump
	ip iLOAD-C vcell iADD ip iSTORE-C
	ip iLOAD
	pc!
label: opJumpZ
	tos iLOAD-C
	w iSTORE-C
	--sp
	sp iLOAD
	tos iSTORE
	w iLOAD-C
	opJump 2/ iJUMPZ
	ip iLOAD-C vcell iADD ip iSTORE-C
	next branch
label: opHalt
	halt
label: opBye
	reset
label: opAnd
	sp iLOAD
	tos 2/ iAND
	tos iSTORE-C
	--sp
	next branch
label: opOr
	sp iLOAD
	tos 2/ iOR
	tos iSTORE-C
	--sp
	next branch
label: opXor
	sp iLOAD
	tos 2/ iXOR
	tos iSTORE-C
	--sp
	next branch
label: opInvert
	tos iLOAD-C
	set 2/ iXOR
	tos iSTORE-C
	next branch
label: opAdd
	sp iLOAD
	tos 2/ iADD
	tos iSTORE-C
	fdefault
	--sp
	next branch
label: opLOAD
	tos iLOAD
	next branch
label: opSTORE
	sp iLOAD
	tos iSTORE
	--sp
	sp iLOAD
	tos iSTORE-C
	--sp
	next branch
\ Also need: um+ >r r> r@ r sp lshift rshift 1+ 1-
\ 'lshift' and 'rshift' will need to convert the shift amount 

: lit opPush branch t, ;

label: cold
	there 2/ <cold> t!
	2048 lit 8801 lit opSTORE branch
	5 lit
	6 lit
	opAdd branch

	opHalt branch

save-hex bit.hex

only forth definitions decimal
.( DONE ) cr
bye

