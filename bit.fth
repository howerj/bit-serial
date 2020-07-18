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

wordlist constant meta.1
wordlist constant target.1
wordlist constant assembler.1

: (order) ( w wid*n n -- wid*n w n )
   dup if
    1- swap >r recurse over r@ xor if
     1+ r> -rot exit then r> drop then ;
: -order ( wid -- ) get-order (order) nip set-order ;
: +order ( wid -- ) dup >r -order get-order r> swap 1+ set-order ;

get-current meta.1 set-current drop
meta.1 +order

000a constant =lf
   2 constant =cell
2000 constant size
  40 constant =stksz
  80 constant =buf

create tflash size cells here over erase allot

variable tdp
variable tep
variable tlast
size =cell - tep !
0 tlast !

: there tdp @ ;
: tc! tflash + c! ;
: tc@ tflash + c@ ;
: t! over ff and over tc! swap 8 rshift swap 1+ tc! ;
: t@ dup tc@ swap 1+ tc@ 8 lshift or ;
: talign there 1 and tdp +! ;
: tc, there tc! 1 tdp +! ;
: t, there t! 2 tdp +! ;
: $literal" [char] " word count dup tc, 0 ?do count tc, loop drop talign ;
: tallot tdp +! ;
: org tdp ! ;
: thead 
  talign 
  tlast @ t, 
  there  tlast !
  parse-word dup tc, 0 ?do count tc, loop drop talign ;

: hex# ( u -- addr len )  0 <# base @ >r hex =lf hold # # # # r> base ! #> ;
: save-hex ( <name> -- )
  parse-word w/o create-file throw
  there 0 do i t@  over >r hex# r> write-file throw =cell +loop
   close-file throw ;
: save-target ( <name> -- )
  parse-word w/o create-file throw >r
   tflash there r@ write-file throw r> close-file ;
: .h base @ >r hex     u. r> base ! ;
: .d base @ >r decimal u. r> base ! ;
: twords
   cr tlast @
   begin
      dup tflash + count 1f and type space =cell - t@
   ?dup 0= until ;
: .stat ." words> " twords cr ." used> " there dup ." 0x" .h ." / " .d cr ;
: .end only forth definitions decimal ;

: tvar   create there , t, does> @ ;
: label: create there ,    does> @ ;

\ TODO Place these in an assembler vocabulary, and drop the 'a' prefix
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
: halt!  flgHlt iLITERAL flags! ;
: reset! flgR   iLITERAL flags! ;
: branch  2/ iJUMP ;
: ?branch 2/ iJUMPZ ;
: zero? flags? 2 iAND ;

\ TODO Place these in an assembler vocabulary, and drop the 'a' prefix
: abegin there ;
: auntil ?branch ;
: aagain branch ;
: aif there 0 ?branch ;
: askip there 0 branch ;
: athen abegin 2/ over t@ or swap t! ;
: aelse askip swap athen ;
: awhile aif swap ;
: arepeat branch athen ;

0 t,  \ must be 0 ('0 iOR'  works in either indirect or direct mode)
1 t,  \ must be 1 ('1 iADD' works in either indirect or direct mode)
2 t,  \ must be 2 ('2 iADD' works in either indirect or direct mode)
label: entry
0 t,  \ our actual entry point, will be set later

FFFF tvar set \ all bits set, -1
0 tvar <cold> \ entry point of virtual machine program, set later on
0 tvar ip     \ instruction pointer
0 tvar w      \ working pointer
0 tvar t      \ temporary register
0 tvar tos    \ top of stack
0 tvar h      \ dictionary pointer
0 tvar pwd    \ previous word pointer
0 tvar state  \ compiler state
0 tvar hld    \ hold space pointer
10 tvar base  \ input/output radix, default = 16
label: RSTACK \ Return stack start, grows upwards
=stksz tallot
label: VSTACK \ Variable stack *end*, grows downwards
=stksz tallot
VSTACK =stksz + 2/ tvar sp  \ variable stack pointer
RSTACK          2/ tvar rp  \ return stack pointer
0 tvar #tib    \ terminal input buffer
label: TERMBUF
=buf   tallot
1000 tvar tx-full-mask
2000 tvar tx-write-mask
100 tvar rx-empty-mask
400 tvar rx-re-mask
FF  tvar low-byte-mask

\ TODO: add to assembler vocabulary
: fdefault flgInd iLITERAL flags! ;
: vcell 1 ( cell '1' should contain '1' ) ;
: -vcell set 2/ ;
: pc! 0 iSET ; ( acc -> pc )
: --sp sp iLOAD-C  vcell iADD sp iSTORE-C ;
: ++sp sp iLOAD-C -vcell iADD sp iSTORE-C fdefault ;
: --rp rp iLOAD-C -vcell iADD rp iSTORE-C fdefault ;
: ++rp rp iLOAD-C  vcell iADD rp iSTORE-C ;

	\ TODO: Set return and variable stacks, and other variables
label: start
	start 2/ C000 or entry t!
	fdefault
	<cold> iLOAD-C
	ip iSTORE-C
	\ -- fall-through --
label: next
	fdefault
	ip iLOAD-C
	w iSTORE-C
	ip iLOAD-C
	1 iADD
	ip iSTORE-C
	w iLOAD-C pc! \ jump to next token

label: {nest} ( accumulator must contain '0 iGET' )
	w iSTORE-C ( store '0 iGET' into working pointer )
	++rp
	ip iLOAD-C
	rp iSTORE
	w iLOAD-C
	2 iADD
	ip iSTORE-C
	next branch

label: {unnest}
	rp iLOAD
	w iSTORE-C
	--rp
	w iLOAD-C
	ip iSTORE-C
	next branch
	
: nest 0 iGET {nest} branch ;
: unnest {unnest} branch ;

: t: ( "name" -- : forth only routine )
  >in @ thead >in !
    get-current >r target.1 set-current create
    r> set-current CAFEBABE talign there , 
    nest
    does> @ branch ( really a call ) ;
: t; CAFEBABE <> if abort" unstructured" then unnest ; 

: a: ( "name" -- : assembly only routine ) 
  >in @ thead >in !
  get-current >r target.1 set-current create
   r> set-current ( CAFED00D ) talign there , assembler.1 +order 
   does> @ branch  ;
: a; ( CAFED00D <> if abort" unstructured" then ) next branch assembler.1 -order ;
: ha: ( "name" -- : assembly only routine, no header )
     ( CAFED00D <> if abort" unstructured" then )
     create talign there ,  
     assembler.1 +order
     does> @ branch ;

\ TODO: hide/unhide vocabs depending in t:/a:/ha:
target.1 +order

ha: opPush
	++sp
	tos iLOAD-C
	sp iSTORE
	
	ip iLOAD-C
	w iSTORE-C
	w iLOAD
	tos iSTORE-C
	ip iLOAD-C 1 iADD ip iSTORE-C
	a;

ha: opJump
	ip iLOAD
	ip iSTORE-C
	a;

ha: opJumpZ
	tos iLOAD-C
	w iSTORE-C
	sp iLOAD
	tos iSTORE-C
	--sp
	w iLOAD-C
	zero?
	aif
		ip iLOAD
		ip iSTORE-C
	aelse
		ip iLOAD-C 1 iADD ip iSTORE-C
	athen
	a;

: begin talign there ;
: until talign opJumpZ 2/ t, ;
: again talign opJump  2/ t, ;
: if opJumpZ there 0 t, ;
\ : skip there branch ;
\ : then begin 2/ over t@ or swap t! ;
\ : else skip swap then ;
\ : while if swap ;
\ : repeat branch then ;

a: halt
	halt!

a: bye
	reset!

a: and
	sp iLOAD
	tos 2/ iAND
	tos iSTORE-C
	--sp
	a;

a: or
	sp iLOAD
	tos 2/ iOR
	tos iSTORE-C
	--sp
	a;

a: xor 
	sp iLOAD
	tos 2/ iXOR
	tos iSTORE-C
	--sp
	a;

a: invert
	tos iLOAD-C
	set 2/ iXOR
	tos iSTORE-C
	a;

a: +
	sp iLOAD
	tos 2/ iADD
	tos iSTORE-C
	fdefault
	--sp
	a;

\ NOTE: @/! cannot perform I/O operations, we will need new words for that, as
\ they cannot write to the top bit.

a: @
	tos iLOAD-C
	1 iRSHIFT
	tos iSTORE-C
	tos iLOAD
	a;

a: !
	sp iLOAD
	1 iRSHIFT
	tos iSTORE-C
	tos iSTORE
	--sp
	sp iLOAD
	tos iSTORE-C
	--sp
	a;

( a: c@
	tos iLOAD-C
	1 iAND zero? aif

	aelse

	athen
	
	a;

a: c!
	a; )

a: dup
	++sp
	tos iLOAD-C
	sp iSTORE
	a;

a: drop
	sp iLOAD
	tos iSTORE-C
	--sp
	a;

a: swap
	sp iLOAD
	w iSTORE-C
	tos iLOAD-C
	sp iSTORE
	w iLOAD-C
	tos iSTORE-C
	a;

a: 1+
	tos iLOAD-C
	1 iADD
	tos iSTORE-C
	a;

a: 1-
	tos iLOAD-C
	set 2/ iADD
	tos iSTORE-C
	a;

a: >r
	++rp
	tos iLOAD-C
	rp iSTORE
	sp iLOAD
	tos iSTORE-C
	--sp
	a;
	
a: r>
	--rp
	rp iLOAD
	w iSTORE-C
	++sp
	tos iLOAD-C
	sp iSTORE
	w iLOAD-C
	tos iSTORE-C
	a;

a: r@
	++sp
	tos iLOAD-C
	sp iSTORE
	rp iLOAD-C
	tos iSTORE-C
	a;


a: tx! ( ch -- )
	\ wait until not full
	abegin
		801 iGET
		tx-full-mask 2/ iAND
		zero?
	auntil
	tx-write-mask iLOAD-C
	tos 2/ iOR
	\ write byte
	801 iSET
	sp iLOAD
	tos iSTORE-C
	--sp
	a;

a: rx? ( -- ch -1 | 0 )
	++sp
	tos iLOAD-C
	sp iSTORE

	801 iGET
	rx-empty-mask 2/ iAND
	aif
		0 iLITERAL
		tos iSTORE-C
	aelse
		++sp
		rx-re-mask iLOAD-C
		801 iSET
		801 iGET
		low-byte-mask 2/ iAND
		sp iSTORE
		set 2/ iLOAD-C
		tos iSTORE-C
	athen
	a;

\ Also need: swap drop dup um+ r@ r sp lshift rshift opBranch opBranch?
\ 'lshift' and 'rshift' will need to convert the shift amount, also need the
\ following words to implement a complete(ish) Forth interpreter; parse, word,
\ cr, >number, <#, #, #S, #>, ., .s, ",", if, else, then, begin, until, [,
\ ], \, (, .", :, ;, here, <, >, u>, u<, =, <>, (and perhaps a few more...).
\ 
\ lshift/rshift probably need a lookup table to convert 0-16 to a bit-pattern

: lit         opPush t, ;
: char   char opPush t, ;
: [char] char opPush t, ;

\ TODO: need a more efficient way of creating variables...
a: here  
	++sp
	tos iLOAD-C
	sp iSTORE
	h iLOAD
	tos iSTORE-C 
	a;

t: negate 1- invert t;
t: - negate + t;
t: key? rx? t;
t: key begin rx? until t;
a: [ 0 iLITERAL state iSTORE-C a; ( immediate )
a: ] 1 iLITERAL state iSTORE-C a; 
a: 0= tos iLOAD-C zero? aif set iLOAD-C aelse 0 iLOAD-C athen tos iSTORE-C a;
t: = xor 0= t; 
t: <> = 0= t;
a: um+ a;
t: interpret t;
t: quit t;
t: type t;
\ TODO: Hex only numeric input/output (only requires power of 2 division)
\ TODO: Implement division/multiplication
t: . t;
t: find t;
t: parse t;
t: query t;
t: number t;
t: digit t;
t: emit tx! t;
t: cr D lit emit A lit emit t;
t: ok char O emit char K emit cr t;
t: : t;
t: ; t;
t: immediate t;
\ t: nop t;
\ t: if t;
\ t: else t;
\ t: then t;
\ t: begin t;
\ t: again t;
\ t: until t;
\ t: exit t;

t: cold
	there 2/ <cold> t!

	\ begin key emit again

	3 lit
	begin
		char H emit
		char E emit
		char L emit
		char L emit
		char O emit
		cr
		1- dup 0=
	until
	
	5 lit
	6 lit
	+
	ok
	halt 
	t;

save-hex bit.hex
save-target bit.bin
.stat
.end
.( DONE ) cr
bye

