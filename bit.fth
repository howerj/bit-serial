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

\ get-current meta.1 set-current drop
meta.1 +order definitions

   2 constant =cell
2000 constant size
  40 constant =stksz
  80 constant =buf
0008 constant =bksp
000A constant =lf
000D constant =cr
007F constant =del


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
: .end 

   only forth definitions decimal ;

: tvar   create there , t, does> @ ;
: label: create there ,    does> @ ;
: asm[ assembler.1 +order ;
: ]asm assembler.1 -order ;
: meta[ meta.1 +order definitions ;
: ]meta meta.1 -order ;


\ TODO Place these in an assembler vocabulary, and drop the 'a' prefix

\ assembler.1 +order definitions

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

assembler.1 +order definitions
: begin there ;
: until ?branch ;
: again branch ;
: if there 0 ?branch ;
: skip there 0 branch ;
: then begin 2/ over t@ or swap t! ;
: else skip swap then ;
: while if swap ;
: repeat branch then ;
assembler.1 -order
meta.1 +order definitions

\ assembler.1 -order
\ target.1 +order definitions

0 t,  \ must be 0 ('0 iOR'  works in either indirect or direct mode)
1 t,  \ must be 1 ('1 iADD' works in either indirect or direct mode)
2 t,  \ must be 2 ('2 iADD' works in either indirect or direct mode)
label: entry
0 t,  \ our actual entry point, will be set later

FFFF tvar set \ all bits set, -1
  FF tvar low \ lowest bytes set
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
VSTACK =stksz + 2/ dup tvar sp0 tvar sp  \ variable stack pointer
RSTACK          2/ dup tvar rp0 tvar rp  \ return stack pointer
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

\ The code for the virtual machine proper starts here, it consists of only
\ a few labels, some initialization code in 'start', the code that performs
\ the dispatch in 'vm', and calls/returns in '{nest}' and '{unnest}'.

label: start
	start 2/ C000 or entry t!
	fdefault
	sp0 iLOAD-C sp iSTORE-C
	rp0 iLOAD-C rp iSTORE-C
	<cold> iLOAD-C
	ip iSTORE-C
	\ -- fall-through --
label: vm
	\ TODO: VM sanity checks on variables
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
	vm branch

label: {unnest}
	rp iLOAD
	w iSTORE-C
	--rp
	w iLOAD-C
	ip iSTORE-C
	vm branch
	
: nest 0 iGET {nest} branch ;
: unnest {unnest} branch ;

: ht: ( "name" -- : forth only routine )
	get-current >r target.1 set-current create
	r> set-current CAFEBABE talign there ,
	nest
	does> @ branch ( really a call ) ;

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
   r> set-current ( CAFED00D ) talign there , asm[
   does> @ branch  ;
: a; ( CAFED00D <> if abort" unstructured" then ) vm branch ]asm ;
: ha: ( "name" -- : assembly only routine, no header )
     ( CAFED00D <> if abort" unstructured" then )
     create talign there ,  
     assembler.1 +order
     does> @ branch ;

\ TODO: hide/unhide vocabs depending in t:/a:/ha:
target.1 +order definitions

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
	if
		ip iLOAD
		ip iSTORE-C
	else
		ip iLOAD-C 1 iADD ip iSTORE-C
	then
	a;

ha: opNext
	\ Get r@
	\ if r> 1- >r exit then
	\ jump to next cell location
	a;

meta.1 +order definitions

: begin talign there ;
: until talign opJumpZ 2/ t, ;
: again talign opJump  2/ t, ;
: if opJumpZ there 0 t, ;
: skip opJump there 0 t, ;
: then there 2/ swap t! ;
: else skip swap then ;
: while if ;
: repeat swap again then ;
\ TODO test this
: for >r begin ;
: >mark again there ;
: aft drop >mark begin swap ;
: next opNext , ;

target.1 +order definitions meta.1 +order

a: halt halt! a;
a: bye reset! a;
a: exit unnest a;

ha: lls ( u shift -- u : shift left by number of bits set )
	sp iLOAD
	tos 2/ iLSHIFT
	tos iSTORE-C
	--sp
	a;

ha: lrs ( u shift -- u : shift right by number of bits set )
	sp iLOAD
	tos 2/ iRSHIFT
	tos iSTORE-C
	--sp
	a;

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


a: um+ 
	sp iLOAD
	tos 2/ iADD
	sp iSTORE
	flags?
	flgCy iAND
	if 
		1 iLITERAL
	else
		0 iLITERAL
	then
	tos iSTORE-C
	fdefault a;

\ NOTE: @/! cannot perform I/O operations, we will need new words for that, as
\ they cannot write to the top bit.

a: @
	tos iLOAD-C
	1 iRSHIFT
	tos iSTORE-C
	tos iLOAD
	tos iSTORE-C
	a;

a: !
	tos iLOAD-C
	1 iRSHIFT
	w iSTORE-C
	sp iLOAD
	w iSTORE
	--sp
	sp iLOAD
	tos iSTORE-C
	--sp
	a;

a: c@
	tos iLOAD-C
	1 iRSHIFT
	w iSTORE-C
	w iLOAD
	w iSTORE-C
	tos iLOAD-C
	1 iAND zero? if
		w iLOAD-C
		low 2/ iAND
	else
		w iLOAD-C
		low 2/ iRSHIFT
	then
	tos iSTORE-C
	a;

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

a: over
	sp iLOAD
	w iSTORE-C
	++sp
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
	rp iLOAD
	w iSTORE-C
	--rp
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
	rp iLOAD
	tos iSTORE-C
	a;

\ TODO: Implement an 'io!' and 'io@' word set, then use this to implement
\ 'tx!' and 'rx?', this might save space, and it would be more flexible.

a: tx! ( ch -- )
	\ wait until not full
	begin
		801 iGET
		tx-full-mask 2/ iAND
		zero?
	until
	tos iLOAD-C
	low-byte-mask 2/ iAND
	tos iSTORE-C
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
	if
		0 iLITERAL
		tos iSTORE-C
	else
		++sp
		rx-re-mask iLOAD-C
		801 iSET
		801 iGET
		low-byte-mask 2/ iAND
		sp iSTORE
		set 2/ iLOAD-C
		tos iSTORE-C
	then
	a;



ha: flags
	tos iLOAD-C ( load into accumulator so it sets flags )
	flags?      ( check those flags )
	w iSTORE-C
	++sp
	tos iLOAD-C
	sp iSTORE
	w iLOAD-C
	tos iSTORE-C
	a;

\ Also need: swap drop dup um+ r@ r sp lshift rshift opBranch opBranch?
\ 'lshift' and 'rshift' will need to convert the shift amount, also need the
\ following words to implement a complete(ish) Forth interpreter; parse, word,
\ cr, >number, <#, #, #S, #>, ., .s, ",", if, else, then, begin, until, [,
\ ], \, (, .", :, ;, here, <, >, u>, u<, =, <>, (and perhaps a few more...).
\ 
\ lshift/rshift probably need a lookup table to convert 0-16 to a bit-pattern

meta.1 +order definitions

: lit         opPush t, ;
: [char] char opPush t, ;
: char   char opPush t, ;

target.1 +order definitions meta.1 +order

\ TODO: need a more efficient way of creating variables...
a: [ 0 iLITERAL state iSTORE-C a; ( immediate )
a: ] 1 iLITERAL state iSTORE-C a; 
a: 0= tos iLOAD-C zero? if set iLOAD-C else 0 iLOAD-C then tos iSTORE-C a;

\ ---- --- ---- ---- ---- no more direct assembly ---- ---- ---- ---- ----

assembler.1 -order

t: here h lit @ t;
\ t: sp0 sp0 lit @ t;
\ t: rp0 rp0 lit @ t;
t: nip swap drop t;
t: tuck swap over t;
t: ?dup  dup if dup then exit t; ( w -- w w | 0 )
t: rot  >r swap r> swap t; ( w1 w2 w3 -- w2 w3 w1 )
t: 2drop  drop drop t; ( w w -- )
t: 2dup  over over t; ( w1 w2 -- w1 w2 w1 w2 )
t: = xor 0= t; 
t: <> = 0= t;
t: 0< flags 4 lit and 0= 0= t;
t: negate 1- invert t;
t: - negate + t;
t: < - 0< t;
t: > swap < t;
\ t: <= 1+ < t;
\ t: >= swap <= t;
\ ht: high 8000 lit and t;
\ ht: ovf 2dup - high >r and high r> xor 0= 0= t;
\ <https://community.arm.com/developer/ip-products/processors/b/processors-ip-blog/posts/condition-codes-1-condition-flags-and-codes>
t: u> - flags nip 6 lit and 0= t; \ TODO: fix/buggy
t: u< swap u> t;
\ t: u<= u> 0= t;
\ t: u>= u< 0= t;

t: c! ( c b -- )
	dup 1 lit and if
		dup >r @ 00FF lit and swap FF lit lls or r> !
	else
		dup >r @ FF00 lit and swap FF lit and or r> !
	then t;
t: aligned dup 1 lit and + t;

t: dnegate invert >r invert 1 lit um+ r> + t; ( d -- -d )
t: abs  dup 0< if negate then exit t; ( n -- n )
t: max  2dup > if drop exit then nip t; ( n n -- n )
t: min  2dup < if drop exit then nip t; ( n n -- n )
\ t: within over - >r - r> u< t; ( u ul uh -- t )

t: key? rx? t;
t: key begin rx? until t;
t: count dup 1+ swap c@ t; ( b -- b u )
t: emit tx! t;
t: type ( b u -- )
	 begin dup while
		swap count emit swap 1-
	 repeat
	 2drop t;
\ TODO: Implement division/multiplication
ht: digit F lit and [char] 0 + dup 39 lit u> if 7 lit + then t;
t: bl 20 lit t;
t: u.
 	dup FFF lit lrs digit emit 
	dup  FF lit lrs digit emit 
	dup   F lit lrs digit emit
	                digit emit 
	bl emit t;
t: . dup 0< if [char] - emit negate then u. t; ( d -- )
\ t: cmove ( b1 b2 u -- ) for aft >r dup c@ r@ c! 1+ r> 1+ then next 2drop t;
\ t: pack$ ( b u a -- a ) dup >r 2dup ! 1+ swap cmove r> t;
t: space bl emit t;
t: cr =cr lit emit =lf lit emit t;
ht: ok char O emit char K emit cr t;
t: execute >r t;

\ TODO: Fix/Buggy
ht: ^h ( bot eot cur -- bot eot cur )
	>r over r@ < dup if
		=bksp lit dup emit space emit
	then 
	r> + t;

ht: tap ( bot eot cur c -- bot eot cur )
	dup emit over c! 1+ t;

\ ht: delete? dup =bksp lit = swap =del lit = or 0= t;
ht: ktap ( bot eot cur c -- bot eot cur )
	dup =cr lit xor if
		=bksp lit xor ( delete? ) if
			bl tap exit
		then 
		^h exit
	then drop nip dup t;

ht: k? dup bl - 0< >r FF lit = r> or 0= t;

t: accept ( b u -- b u )
	over + over
	begin
		2dup xor
	while
		\ key dup bl - 7F lit u< if tap else ktap then
		key k? if tap else ktap then
	repeat drop over - t;

\ t: query ( -- ) tib @ 50 lit accept #tib ! drop 0 lit >in ! t;

\ https://wiki.c2.com/?ForthSimplicity
\ : IMMEDIATE?	-1 = ;
\ : NEXTWORD	BL WORD FIND ;
\ : NUMBER,	NUMBER POSTPONE LITERAL ;
\ : COMPILEWORD	DUP IF IMMEDIATE? IF EXECUTE ELSE COMPILE, THEN ELSE NUMBER, THEN ;
\ : ]	BEGIN NEXTWORD COMPILEWORD AGAIN ;
\ : [	R> R> 2DROP ; IMMEDIATE	( Breaks out of compiler into interpret mode again )

\ ht: do$ r> r> dup count + aligned >r swap >r t; ( -- a )
\ ht: string-literal do$ t; ( -- a : do string NB. )
\ ht: print count type t;
\ ht: .string do$ print t;      ( -- : print string  )
\ : ." .string $literal" ;
\ : $" string-literal $literal" ;

\ t: nop t;
\ TODO Arrange so these words have a lower priority then meta-compiler versions
\ t: if t;
\ t: else t;
\ t: then t;
\ t: begin t;
\ t: again t;
\ t: until t;
\ t: ." t;
\ t: : t;
\ t: ; t;
\ t: immediate t;
\ t: interpret t;
\ t: quit t;
\ t: find t;
\ t: parse t;
\ t: query t;
\ t: number t;

\ t: word ( 1depth ) parse ( ?length ) here pack$ t;
\ t: token bl word t;
\ t: pick ?dup if swap >r 1- pick r> swap exit then dup t; 
\ t: .s ( -- ) cr sp@ for aft r@ pick . then next ."  <sp" cr t; ( -- )



\ Test string 'HELLO WORLD'

label: ahoy $literal" HELLO WORLD"

\ t: # dup u. t;

t: cold
	there 2/ <cold> t!

	here u. cr

	\ $" WOOP" u. u. cr
	\ begin here 10 lit accept space type cr again

	ahoy lit count type cr

	5 lit
	6 lit
	+
	ok
	halt 
	t;


there h t!
save-hex bit.hex
save-target bit.bin
.stat
.end
.( DONE ) cr
bye

