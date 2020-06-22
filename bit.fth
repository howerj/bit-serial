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
: label create there , does> @ ;

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
FFFF tvar set
000F tvar nib0
2048 tvar uartWrite
2000 tvar _uwrite

0 tvar r0
0 tvar r1
0 tvar r2
0 tvar sp
0 tvar rp

: save r0 iSTORE-C ;
: load r0 iLOAD-C ;
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

: invert set iXOR ;

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

label entry
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

label end
	\ reset
	halt

save-hex bit.hex

only forth definitions decimal
bye
