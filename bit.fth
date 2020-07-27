( 

Cross Compiler for the bit-serial CPU available a:t

  <https://github.com/howerj/bit-serial> 


This implements a Direct Threaded Code virtual machine on which we can
build a Forth interpreter.

References:

- <https://en.wikipedia.org/wiki/Threaded_code>
- <https://github.com/samawati/j1eforth> 
- <https://github.com/howerj/embed> 
- <https://github.com/howerj/forth-cpu>

TODO:

- Optimizations; move stacks/buffers to end of [8KiB] memory, add a opVar and
opConst VM instruction and use it, size optimizations, implement words for
certain numbers [to decrease image size], ...
- Implement a basic Forth interpreter [done]
- Make the interpreter useful
- Add compiler safety
- vector some words?

)

only forth definitions hex

wordlist constant meta.1
wordlist constant target.1
wordlist constant assembler.1
wordlist constant target.only.1

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
  40 constant =buf
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

: :m meta.1 +order definitions postpone : ;
: ;m postpone ; ; immediate
\ : :a assembler.1 +order definitions postpone : ;
\ : ;a postpone ; ; immediate

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
: thead 
  talign 
  there tlast @ t, tlast !
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
      dup tflash + =cell + count 1f and type space t@
   ?dup 0= until ;
: .stat ( ." words> " twords cr ) ." used> " there dup ." 0x" .h ." / " .d cr ;
: .end only forth definitions decimal ;
: atlast tlast @ ;
: tvar   create there , t, does> @ ;
: label: create there ,    does> @ ;
: asm[ assembler.1 +order ;
: ]asm assembler.1 -order ;
: tdown =cell negate and ;
: word.length $1F and ;
: tnfa =cell + ; ( pwd -- nfa : move to name field address)
: tcfa tnfa dup c@ word.length + =cell + tdown ; ( pwd -- cfa )
: compile-only tlast @ tnfa t@ $20 or tlast @ tnfa t! ; ( -- )
: immediate    tlast @ tnfa t@ $40 or tlast @ tnfa t! ; ( -- )
: t' ' >body @ ;

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
\ : topost target.only.1 +order ' >body @ branch target.only.1 -order ;

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

FFFF tvar set   \ all bits set, -1
  FF tvar low   \ lowest bytes set
0 tvar  <cold>  \ entry point of virtual machine program, set later on
0 tvar  ip      \ instruction pointer
0 tvar  w       \ working pointer
0 tvar  t       \ temporary register
0 tvar  tos     \ top of stack
0 tvar  h       \ dictionary pointer
0 tvar  pwd     \ previous word pointer
0 tvar  {state} \ compiler state
0 tvar  {hld}   \ hold space pointer
10 tvar {base}  \ input/output radix, default = 16
-1 tvar {dpl}   \ number of places after fraction )
0  tvar {in}      \ position in query string
0  tvar {handler} \  throw/catch handler
0  tvar {last}    \ last defined word
label: RSTACK \ Return stack start, grows upwards
=stksz tallot
label: VSTACK \ Variable stack *end*, grows downwards
=stksz tallot
VSTACK =stksz + 2/ dup tvar {sp0} tvar {sp}  \ variable stack pointer
RSTACK          2/ dup tvar {rp0} tvar {rp}  \ return stack pointer
0 tvar #tib    \ terminal input buffer
label: TERMBUF
=buf   tallot
label: {pad}
=buf   tallot
1000 tvar tx-full-mask
2000 tvar tx-write-mask
100 tvar rx-empty-mask
400 tvar rx-re-mask
3   tvar test-mask
FF  tvar low-byte-mask

\ TODO: add to assembler vocabulary
: fdefault flgInd iLITERAL flags! ;
: vcell 1 ( cell '1' should contain '1' ) ;
: -vcell set 2/ ;
: pc! 0 iSET ; ( acc -> pc )
: --sp {sp} iLOAD-C  vcell iADD {sp} iSTORE-C ;
: ++sp {sp} iLOAD-C -vcell iADD {sp} iSTORE-C fdefault ;
: --rp {rp} iLOAD-C -vcell iADD {rp} iSTORE-C fdefault ;
: ++rp {rp} iLOAD-C  vcell iADD {rp} iSTORE-C ;

\ The code for the virtual machine proper starts here, it consists of only
\ a few labels, some initialization code in 'start', the code that performs
\ the dispatch in 'vm', and calls/returns in '{nest}' and '{unnest}'.

label: start
	start 2/ C000 or entry t!
	fdefault
	{sp0} iLOAD-C {sp} iSTORE-C
	{rp0} iLOAD-C {rp} iSTORE-C
	<cold> iLOAD-C
	ip iSTORE-C
	\ -- fall-through --
label: vm
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
	{rp} iSTORE
	w iLOAD-C
	2 iADD
	ip iSTORE-C
	vm branch

label: {unnest}
	{rp} iLOAD
	w iSTORE-C
	--rp
	w iLOAD-C
	ip iSTORE-C
	vm branch
	
: nest 0 iGET {nest} branch ;
: unnest {unnest} branch ;
: =nest {nest} 2/ C000 or ;
: =unnest {unnest} 2/ C000 or ;
: =0iGET F000 ;

: :ht ( "name" -- : forth only routine )
	get-current >r target.1 set-current create
	r> set-current CAFEBABE talign there ,
	nest
	does> @ branch ( really a call ) ;

: :t ( "name" -- : forth only routine )
	>in @ thead >in !
	get-current >r target.1 set-current create
	r> set-current CAFEBABE talign there , 
	nest
	does> @ branch ( really a call ) ;

: :to ( "name" -- : forth only, target only routine )
	>in @ thead >in !
	get-current >r target.only.1 set-current create
	r> set-current there ,
	nest CAFEBABE 
	does> @ branch ;

: ;t CAFEBABE <> if abort" unstructured" then unnest target.only.1 -order ; 

: a: ( "name" -- : assembly only routine, no header )
     CAFED00D
     create talign there ,  
     assembler.1 +order
     does> @ branch ;
: a; CAFED00D <> if abort" unstructured" then vm branch ]asm ;

\ TODO: hide/unhide vocabs depending in :t/a:/ha:
target.1 +order definitions

a: opPush
	++sp
	tos iLOAD-C
	{sp} iSTORE
	
	ip iLOAD-C
	w iSTORE-C
	w iLOAD
	tos iSTORE-C
	ip iLOAD-C 1 iADD ip iSTORE-C
	a;

a: opJump
	ip iLOAD
	ip iSTORE-C
	a;


a: opJumpZ
	tos iLOAD-C
	w iSTORE-C
	{sp} iLOAD
	tos iSTORE-C
	--sp
	w iLOAD-C
	if
		ip iLOAD-C 1 iADD ip iSTORE-C
	else
		ip iLOAD
		ip iSTORE-C
	then
	a;

meta.1 +order definitions
: lit         opPush t, ;
: [char] char opPush t, ;
: char   char opPush t, ;
: =push  [ t' opPush  ] literal 2/ C000 or  ;
: =jump  [ t' opJump  ] literal 2/ C000 or  ;
: =jumpz [ t' opJumpZ ] literal 2/ C000 or  ;
target.1 -order
target.1 +order definitions meta.1 +order

a: opNext
	\ Get r@
	\ if r> 1- >r exit then
	\ jump to next cell location
	{rp} iLOAD
	if
		set 2/ iADD
		{rp} iSTORE
		fdefault
		ip iLOAD
		ip iSTORE-C
	else
		ip iLOAD-C 1 iADD ip iSTORE-C
		--rp
	then
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
: aft drop skip begin swap ;
: next talign opNext 2/ t, ;

target.1 +order definitions meta.1 +order

\ TODO: Fix bug -- cannot execute assembly instructions
a: halt halt! a;
a: bye reset! a;
a: exit unnest a;

a: lls ( u shift -- u : shift left by number of bits set )
	{sp} iLOAD
	tos 2/ iLSHIFT
	tos iSTORE-C
	--sp
	a;

a: lrs ( u shift -- u : shift right by number of bits set )
	{sp} iLOAD
	tos 2/ iRSHIFT
	tos iSTORE-C
	--sp
	a;

a: and
	{sp} iLOAD
	tos 2/ iAND
	tos iSTORE-C
	--sp
	a;

a: or
	{sp} iLOAD
	tos 2/ iOR
	tos iSTORE-C
	--sp
	a;

a: xor 
	{sp} iLOAD
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
	{sp} iLOAD
	tos 2/ iADD
	tos iSTORE-C
	fdefault
	--sp
	a;


a: um+ 
	{sp} iLOAD
	tos 2/ iADD
	{sp} iSTORE
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
	{sp} iLOAD
	w iSTORE
	--sp
	{sp} iLOAD
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
	{sp} iSTORE
	a;

a: drop
	{sp} iLOAD
	tos iSTORE-C
	--sp
	a;

a: swap
	{sp} iLOAD
	w iSTORE-C
	tos iLOAD-C
	{sp} iSTORE
	w iLOAD-C
	tos iSTORE-C
	a;

a: over
	{sp} iLOAD
	w iSTORE-C
	++sp
	tos iLOAD-C
	{sp} iSTORE
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
	{rp} iSTORE
	{sp} iLOAD
	tos iSTORE-C
	--sp
	a;
	
target.1 +order meta.1 +order definitions
: for talign >r begin ;
: =>r [ t' >r target.1 -order ] literal 2/ C000 or ; target.1 +order
: =next [ t' opNext target.1 -order ] literal 2/ C000 or ;
target.1 +order definitions meta.1 +order

a: r>
	{rp} iLOAD
	w iSTORE-C
	--rp
	++sp
	tos iLOAD-C
	{sp} iSTORE
	w iLOAD-C
	tos iSTORE-C
	a;

a: r@
	++sp
	tos iLOAD-C
	{sp} iSTORE
	{rp} iLOAD
	tos iSTORE-C
	a;

a: rdrop
	--rp
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
	{sp} iLOAD
	tos iSTORE-C
	--sp
	a;

a: rx? ( -- ch -1 | 0 )
	++sp
	tos iLOAD-C
	{sp} iSTORE

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
		{sp} iSTORE
		set 2/ iLOAD-C
		tos iSTORE-C
	then
	a;

\ TODO: need a more efficient way of creating variables...
a: 0= tos iLOAD-C zero? if set iLOAD-C else 0 iLOAD-C then tos iSTORE-C a;
a: execute
	tos iLOAD-C
	w iSTORE-C
	{sp} iLOAD
	tos iSTORE-C
	--sp
	w iLOAD-C
	1 iRSHIFT 
	{nest} branch a;

\ ---- --- ---- ---- ---- no more direct assembly ---- ---- ---- ---- ----

assembler.1 -order

:to halt halt ;t
:to bye bye ;t
:to exit exit ;t
:to and and ;t
:to or or ;t
:to xor xor ;t
:to invert invert ;t
:to + + ;t
:to um+ um+ ;t
:to @ @ ;t
:to ! ! ;t
:to c@ c@ ;t
:to dup dup ;t
:to drop drop ;t
:to swap swap ;t
:to over over ;t
:to 1+ 1+ ;t
:to 1- 1- ;t
:to >r r> swap >r >r ;t
:to r> r> r> swap >r ;t
:to r@ r> r@ swap >r ;t
:to rdrop rdrop ;t
:to tx! tx! ;t
:to rx? rx? ;t
:to 0= 0= ;t
:to execute execute ;t
\ TODO: Create special variables for these.
:t here h lit @ ;t
:t sp0 {sp0} lit @ ;t
:t rp0 {rp0} lit @ ;t
:t sp@ {sp} lit @ ;t
:t rp@ {rp} lit @ ;t
:t sp! {sp} lit ! ;t
:t rp! {rp} lit ! ;t
:t base {base} lit ;t
:t dpl {dpl} lit ;t
:t hld {hld} lit ;t
:t bl 20 lit ;t
:t pad {pad} lit ;t
:t >in {in} lit ;t
:t hex     $10 lit base ! ;t
:t decimal  $a lit base ! ;t
:t source TERMBUF lit #tib lit @ ;t ( -- b u )
:t tib source drop ;t
:t last {last} lit @ ;t
:t state {state} lit ;t
:t [ 0 lit state ! ;t immediate
:t ] -1 lit state ! ;t 
:t nip swap drop ;t
:t tuck swap over ;t
:t ?dup  dup if dup then exit ;t ( w -- w w | 0 )
:t rot >r swap r> swap ;t        ( w1 w2 w3 -- w2 w3 w1 )
:t -rot rot rot ;t               ( w1 w2 w3 -- w2 w3 w1 )
:t 2drop  drop drop ;t           ( w w -- )
:t 2dup  over over ;t            ( w1 w2 -- w1 w2 w1 w2 )
:t 2>r r> swap >r swap >r >r ;t
:t 2r> r> r> swap r> swap >r ;t
:t +! tuck @ + swap ! ;t ( n a -- )
:t 1+! 1 lit swap +! ;t
:t 1-! -1 lit swap +! ;t
:t = xor 0= ;t 
:t <> = 0= ;t
:t 0<> 0= 0= ;t
:t 0>= 8000 lit and 0= ;t
:t 0< 8000 lit and 0= 0= ;t
:t negate 1- invert ;t
:t - negate + ;t
:t < - 0< ;t
:t > swap < ;t
:t 0> 0 lit > ;t
:t 2* 1 lit lls ;t
:to 2/ 1 lit lrs ;t
:t cell 2 lit ;t
:t cell+ 2 lit + ;t
:t cell- 2 lit - ;t
:t cells 2* ;t
:t chars 1 lit lrs ;t
:t u< 2dup 0>= swap 0>= xor >r < r> xor ;t
:t u> swap u< ;t
:t aligned dup 1 lit and + ;t
:t align here aligned h lit ! ;t
:t depth sp0 sp@ - 2 lit - ;t
:t c! ( c b -- )
	dup 1 lit and if
		dup >r @ 00FF lit and swap FF lit lls or r> !
	else
		dup >r @ FF00 lit and swap FF lit and or r> !
	then ;t
:t count dup 1+ swap c@ ;t ( b -- b u )
:t , here dup cell+ h lit ! ! ;t ( u -- )
:t allot aligned h lit +! ;t     ( u -- )
:t c, here c! h lit 1+! ;t       ( c -- )
:t dnegate invert >r invert 1 lit um+ r> + ;t ( d -- -d )
:t d0= or 0= ;t                          ( d -- f )
:t d+ >r swap >r um+ r> + r> + ;t        ( d d -- d )
:t abs  dup 0< if negate then exit ;t    ( n -- n )
:t max  2dup > if drop exit then nip ;t  ( n n -- n )
:t min  2dup < if drop exit then nip ;t  ( n n -- n )
:t within over - >r - r> u< ;t           ( u ul uh -- t )
:t /string over min rot over + -rot - ;t ( b u1 u2 -- b u : advance string )
:t +string 1 lit /string ;t              ( b u -- b u : advance string by 1 )
:t pick ?dup if swap >r 1- pick r> swap exit then dup ;t \ TODO replace with more efficient version
:t ndrop for aft drop then next ;t \ TODO replace with more efficient version
:t catch  ( xt -- exception# | 0 : return addr on stack )
  sp@ >r        ( xt : save data stack depth )
  {handler} lit @ >r  ( xt : and previous handler )
  rp@ {handler} lit ! ( xt : set current handler )
  execute       (      execute returns if no throw )
  r> {handler} lit !  (      restore previous handler )
  rdrop         (      discard saved stack ptr )
  0 lit ;t      ( 0  : normal completion )
:t throw  ( ??? exception# -- ??? exception# )
  ?dup if ( exc# \ 0 throw is no-op )
    {handler} lit @ rp! ( exc# : restore prev return stack )
    r> {handler} lit !  ( exc# : restore prev handler )
    r> swap >r ( saved-sp : exc# on return stack )
    sp@ swap - ndrop r>   ( exc# : restore stack )
    ( return to the caller of catch because return )
    ( stack is restored to the state that existed )
    ( when catch began execution )
  then ;t
:t um* ( u u -- ud )
	0 lit swap ( u1 0 u2 ) $F lit
	for dup um+ >r >r dup um+ r> + r>
		if >r over um+ r> + then
	next rot drop ;t
:t *    um* drop ;t  ( n n -- n )
:t um/mod ( ud u -- ur uq )
  \ ?dup 0= if $A lit -throw exit then
  2dup u<
  if negate $F lit
    for >r dup um+ >r >r dup um+ r> + dup
      r> r@ swap >r um+ r> or
      if >r drop 1+ r> else drop then r>
    next
    drop swap exit
  then 2drop drop -1 lit dup ;t
:t m/mod ( d n -- r q ) \ floored division
  dup 0< dup >r
  if
    negate >r dnegate r>
  then
  >r dup 0< if r@ + then r> um/mod r>
  if swap negate swap exit then ;t
\ :t */ >r um* r> m/mod nip ;t ( n n n -- )
:t /mod  over 0< swap m/mod ;t ( n n -- r q )
:t mod  /mod drop ;t           ( n n -- r )
:t /    /mod nip ;t            ( n n -- q )
:t key? rx? ;t
:t key begin rx? until ;t
:t emit tx! ;t
:t type begin dup while swap count emit swap 1- repeat 2drop ;t ( b u -- )
:t fill  swap for swap aft 2dup c! 1+ then next 2drop ;t     ( b u c -- )
:t cmove  for aft >r dup c@ r@ c! 1+ r> 1+ then next 2drop ;t ( b1 b2 u -- )
:t pack$  dup >r 2dup ! 1+ swap cmove r> ;t ( b u a -- a )
:t space bl emit ;t
:t cr =cr lit emit =lf lit emit ;t
:t ok space char o emit char k emit cr ;t
:t ^h ( bot eot cur -- bot eot cur )
	>r over r@ < dup if
		=bksp lit dup emit space emit
	then 
	r> + ;t
:t tap dup emit over c! 1+ ;t ( bot eot cur c -- bot eot cur )
:t ktap ( bot eot cur c -- bot eot cur )
	dup =cr lit xor if
		=bksp lit xor ( delete? ) if
			bl tap exit
		then 
		^h exit
	then drop nip dup ;t
:t accept ( b u -- b u )
	over + over
	begin
		2dup xor
	while
		key dup bl - $5F lit u< if tap else ktap then
	repeat drop over - ;t
:t query TERMBUF lit =buf lit accept #tib lit ! drop 0 lit >in ! ;t
:t -trailing ( b u -- b u : remove trailing spaces )
  for
    aft bl over r@ + c@ <
      if r> 1+ exit then
    then
  next 0 lit ;t
:ht lookfor ( b u c xt -- b u : skip until *xt* test succeeds )
  swap >r -rot
  begin
    dup
  while
    over c@ r@ - r@ bl = 4 lit pick execute
    if rdrop rot drop exit then
    +string
  repeat rdrop rot drop ;t
:ht no-match if 0> exit then 0<> ;t ( n f -- t )
:ht match no-match invert ;t        ( n f -- t )
:ht parser ( b u c -- b u delta )
   >r over r> swap 2>r
   r@ t' no-match lit lookfor 2dup
   r> t' match    lit lookfor swap r> - >r - r> 1+ ;t
:t parse ( c -- b u ; <string> )
    >r tib >in @ + #tib lit @ >in @ - r@ parser >in +!
    r> bl = if -trailing then 0 lit max ;t
:t nchars                              ( +n c -- : emit c n times )
   swap 0 lit max for aft dup emit then next drop ;t
:t spaces bl nchars ;t ( +n -- )
:t digit 9 lit over < 7 lit and + [char] 0 + ;t         ( u -- c )
:t hold hld @ 1- dup hld ! c! ( hld @ pad $80 - u> ?exit $11 -throw ) ;t ( c -- )
:t extract dup >r um/mod r> swap >r um/mod r> rot ;t  ( ud ud -- ud u )
:t #> 2drop hld @ pad over - ;t                ( w -- b u )
:t #  ( 2 ?depth ) 0 lit base @ extract digit hold ;t  ( d -- d )
:t #s begin # 2dup d0= until ;t               ( d -- 0 )
:t <# pad hld ! ;t                            ( -- )
:t sign 0< 0= if exit then [char] - hold ;t ( n -- )
:t (.) ( n -- b u : convert a signed integer to a numeric string )
  dup >r abs 0 lit <# #s r> sign #> ;t
:t (u.) 0 lit <# #s #> ;t             ( u -- b u : turn *u* into number string )
:t u.r >r (u.) r> over - spaces type ;t ( u +n -- : print u right justified by +n)
\ ( :  .r >r (.)( r> over - spaces type ;t      ( n n -- : print n, right justified by +n )
:t u.  (u.) space type ;t  ( u -- : print unsigned number )
:t  .  (.) space type ;t                  ( n -- print number )
:t digit? ( c base -- u f )
  >r [char] 0 - 9 lit over <
  if
    7 lit -
    dup $A lit < or
  then dup r> u< ;t
:t >number ( ud b u -- ud b u : convert string to number )
  begin
    ( get next character )
    2dup 2>r drop c@ base @ digit?
    0= if                                   ( d char )
      drop                                  ( d char -- d )
      2r>                                   ( restore string )
      exit                                  ( ..exit )
    then                                    ( d char )
    swap base @ um* drop rot base @ um* d+  ( accumulate digit )
    2r>                                     ( restore string )
    +string dup 0=                          ( advance string and test for end )
  until ;t
:t number? ( a u -- d -1 | a u 0 )
  -1 lit dpl !
  base @ >r
  over c@ [char] - = dup >r if     +string then
  over c@ [char] $ =        if hex +string then
  2>r 0 lit dup 2r>
  begin
    >number dup
  while over c@ [char] .  ( fsp @ ) xor
    if rot drop rot r> 2drop 0 lit r> base ! exit then
    1- dpl ! 1+ dpl @
  repeat 2drop r> if dnegate then r> base ! -1 lit ;t
:t compare ( a1 u1 a2 u2 -- n : string equality )
  rot
  over - ?dup if >r 2drop r> nip exit then
  for ( a1 a2 )
    aft
      count rot count rot - ?dup
      if rdrop nip nip exit then
    then
  next 2drop 0 lit ;t
:t do$ 2r> 1 lit lls dup count + aligned 1 lit lrs >r swap >r ;t ( -- a )
:t lit$ do$ ;t ( -- a : do string NB. )
:t .$ do$ count type ;t      ( -- : print string  )
: ." .$ $literal ;
: $" lit$ $literal ; \ "
\ :t throw . [char] ? emit cr reset! ;t \ TODO: Implement correctly!
:t .s depth for aft r@ pick . then  next ."  <sp" cr ;t
:t nfa cell+ ;t
:t cfa nfa dup c@ $1F lit and + cell+ 2 lit negate and ;t ( pwd -- cfa )
:t immediate? nfa $40 lit swap @ and 0<> ;t ( pwd -- t : is word immediate? )
:t compile-only? nfa $20 lit swap @ and 0<> ;t    ( pwd -- t : is word compile only? )
:t (search-wordlist) ( a wid -- PWD PWD 1|PWD PWD -1|0 a 0: find word in WID )
  swap >r dup
  begin
    dup
  while
    dup nfa count $9F lit ( $1F:word-length + $80:hidden ) and r@ count compare 0=
    if ( found! )
      rdrop
      dup immediate? 1 lit or negate exit
    then
    nip dup @
  repeat
  2drop 0 lit r> 0 lit ;t
:t search-wordlist (search-wordlist) rot drop ;t
:t (find) last (search-wordlist) ;t
:t find (find) rot drop ;t
:t literal =push lit , , ;t
:t (literal) state @ 0= if exit then literal ;t
:t compile, 1 lit lrs align C000 lit or , ;t
:t ?found 0= if space count type [char] ? emit cr -D lit throw then ;t ( u f -- )
:t interpret
  find ?dup if
    state @
    if
      0> if cfa execute exit then \ <- immediate word are executed
      cfa compile, exit               \ <- compiling word are...compiled.
    then
    drop \ ?compile     \ <- check it's not a compile only word word
    cfa execute exit  \ <- if its not, execute it, then exit *interpreter*
  then
  \ not a word
  dup >r count number? if rdrop \ it's a number!
    dpl @ 0< if \ <- dpl will -1 if its a single cell number
       drop     \ drop high cell from 'number?' for single cell output
    else        \ <- dpl is not -1, it's a double cell number
       state @ if swap then
       (literal) \ (literal) is executed twice if it's a double
    then
    (literal) exit
  then
  r> 0 lit ?found \ Could vector ?found here, to handle arbitrary words
  ;t 
:t word ( 1depth ) parse ( ?length ) here pack$ ;t
:t token bl word ;t
:t ?depth drop ;t \ TODO: implement
:t eval begin token dup c@ while interpret 0 lit ?depth repeat drop ok ;t
:t prequit [ 0 lit >in ! ( sp0 sp! ) ;t
:t ?error ?dup if space u. [char] ? emit then ;t
:t quit prequit begin query t' eval lit catch ?error again ;t
:t words last begin dup nfa count 1f lit and space type @ ?dup 0= until ;t
:t ?nul dup c@ if exit then -A lit throw ;t
:t ?unique ( dup find nip if ." redefined" cr then ) ;t
:to see token find ?found begin dup @ =unnest lit <> while dup @ u. cell+ repeat @ u. ;t
:to : align here last , {last} lit ! 
    token ?nul ?unique count + h lit ! align 
    =0iGET lit , =nest lit , ] ( 6666 lit ) ;t
:to ; [ ( 6666 lit <> if -16 lit throw then ) =unnest lit , ;t immediate
:to begin align here ;t immediate compile-only
:to until align =jumpz lit , 1 lit lrs , ;t immediate compile-only
:to again align =jump  lit , 1 lit lrs , ;t immediate compile-only
:to if align =jumpz lit , here 0 lit , ;t immediate compile-only
:t skip =jump lit , 0 lit , ;t
\ :to else skip swap topost then ;t immediate compile-only
:to then here 1 lit lrs swap ! ;t immediate compile-only
:to for align =>r lit , here ;t immediate compile-only
:to next align =next lit , 1 lit lrs , ;t immediate compile-only
\ :to aft drop skip begin swap ;t
\ :to while if ;t
\ :to repeat swap again then ;t
\ :to next talign opNext 2/ t, ;t
:to ' token find ?found cfa state @ if (literal) then ;t immediate
\ :t compile r> dup @ , cell+ >r ;t compile-only
\ :to ." compile .$ [char] " word count + h lit ! align ;t immediate compile-only
\ :to $" compile lit$ [char] " word count + h lit ! align ;t immediate compile-only  \ "
:to ( [char] ) parse 2drop ;t immediate ( "comment" -- discard until parenthesis )
:to \ source drop @ >in ! ;t immediate  ( "comment" -- discard until end of line )
:to immediate last nfa @ $40 lit or last nfa ! ;t
:t dump ( a u -- )
	begin
		dup
	while
		dup F lit and 0= if cr then
		over c@ 
		2 lit u.r
		space
		+string
	repeat 2drop cr ;t
\ TODO: Make a VHDL simulation only program?
:t cold \ Actual Program Entry Point
	there 2/ <cold> t!
	hex
	cr
	." eForth v1.0.0" here u. cr
	ok quit halt ;t

there h t!
atlast {last} t!
save-hex bit.hex
save-target bit.bin
.stat
.end
.( DONE ) cr
bye

