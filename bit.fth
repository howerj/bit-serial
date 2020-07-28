\ 
\ Cross Compiler for the bit-serial CPU available a:t
\ 
\   <https://github.com/howerj/bit-serial>
\ 
\ 
\ This implements a Direct Threaded Code virtual machine on which we can
\ build a Forth interpreter.
\ 
\ References:
\ 
\ - <https://en.wikipedia.org/wiki/Threaded_code>
\ - <https://github.com/samawati/j1eforth>
\ - <https://github.com/howerj/embed>
\ - <https://github.com/howerj/forth-cpu>
\ 

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

: :m meta.1 +order definitions : ;
: ;m postpone ; ; immediate
:m there tdp @ ;m
:m tc! tflash + c! ;m
:m tc@ tflash + c@ ;m
:m t! over ff and over tc! swap 8 rshift swap 1+ tc! ;m
:m t@ dup tc@ swap 1+ tc@ 8 lshift or ;m
:m talign there 1 and tdp +! ;m
:m tc, there tc! 1 tdp +! ;m
:m t, there t! 2 tdp +! ;m
:m $literal [char] " word count dup tc, 0 ?do count tc, loop drop talign ;m
:m tallot tdp +! ;m
:m thead
  talign
  there tlast @ t, tlast !
  parse-word dup tc, 0 ?do count tc, loop drop talign ;m
:m hex# ( u -- addr len )  0 <# base @ >r hex =lf hold # # # # r> base ! #> ;m
:m save-hex ( <name> -- )
  parse-word w/o create-file throw
  there 0 do i t@  over >r hex# r> write-file throw =cell +loop
   close-file throw ;m
:m save-target ( <name> -- )
  parse-word w/o create-file throw >r
   tflash there r@ write-file throw r> close-file ;m
:m .h base @ >r hex     u. r> base ! ;m
:m .d base @ >r decimal u. r> base ! ;m
:m twords
   cr tlast @
   begin
      dup tflash + =cell + count 1f and type space t@
   ?dup 0= until ;m
:m .stat 
	0 if
		." target: "      target.1      +order words cr cr
		." target-only: " target.only.1 +order words cr cr
		." assembler: "   assembler.1   +order words cr cr
		." meta: "        meta.1        +order words cr cr
	then
	." used> " there dup ." 0x" .h ." / " .d cr ;m
:m .end only forth definitions decimal ;m
:m atlast tlast @ ;m
:m tvar   get-current >r meta.1 set-current create r> set-current there , t, does> @ ;m
:m label: get-current >r meta.1 set-current create r> set-current there ,    does> @ ;m
:m tdown =cell negate and ;m
:m tnfa =cell + ;m ( pwd -- nfa : move to name field address)
:m tcfa tnfa dup c@ $1F and + =cell + tdown ;m ( pwd -- cfa )
:m compile-only tlast @ tnfa t@ $20 or tlast @ tnfa t! ;m ( -- )
:m immediate    tlast @ tnfa t@ $40 or tlast @ tnfa t! ;m ( -- )
:m t' ' >body @ ;m
:m call 2/ C000 or ;
\ TODO Place these in an assembler vocabulary, and drop the 'a' prefix

\ assembler.1 +order 

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
: halt!  flgHlt iLITERAL flags! ;
: reset! flgR   iLITERAL flags! ;
: branch  2/ iJUMP ;
: ?branch 2/ iJUMPZ ;
: zero? flags? 2 iAND ;
: topost target.only.1 +order ' >body @ branch target.only.1 -order  ;
:m postpone t' branch ;m

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
label: {pad}
=buf   tallot
VSTACK =stksz + 2/ dup tvar {sp0} tvar {sp}  \ variable stack pointer
RSTACK          2/ dup tvar {rp0} tvar {rp}  \ return stack pointer
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
: --sp {sp} iLOAD-C  vcell iADD {sp} iSTORE-C ;
: ++sp {sp} iLOAD-C -vcell iADD {sp} iSTORE-C fdefault ;
: --rp {rp} iLOAD-C -vcell iADD {rp} iSTORE-C fdefault ;
: ++rp {rp} iLOAD-C  vcell iADD {rp} iSTORE-C ;

label: start
	start call entry t!
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
	w iLOAD-C 
	0 iSET \ jump to next token

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

:m nest 0 iGET {nest} branch ;m
:m unnest {unnest} branch ;m
:m =nest {nest} call ;m
:m =unnest {unnest} call ;m
:m =0iGET F000 ;m

:m :ht ( "name" -- : forth only routine )
	get-current >r target.1 set-current create
	r> set-current CAFEBABE talign there ,
	nest
	does> @ branch ( really a call ) ;m

:m :t ( "name" -- : forth only routine )
	>in @ thead >in !
	get-current >r target.1 set-current create
	r> set-current CAFEBABE talign there ,
	nest
	does> @ branch ( really a call ) ;m

:m :to ( "name" -- : forth only, target only routine )
	>in @ thead >in !
	get-current >r target.only.1 set-current create r> set-current 
	there ,
	nest CAFEBABE
	does> @ branch ;m

:m ;t CAFEBABE <> if abort" unstructured" then unnest target.only.1 -order ;

:m a: ( "name" -- : assembly only routine, no header )
	CAFED00D
	target.1 +order definitions
	create talign there ,
	assembler.1 +order
	does> @ branch ;m
:m a; CAFED00D <> if abort" unstructured" then vm branch assembler.1 -order ;m

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

a: opNext
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

:m lit         opPush t, ;m
:m [char] char opPush t, ;m
:m char   char opPush t, ;m
:m =push  [ t' opPush  ] literal call  ;m
:m =jump  [ t' opJump  ] literal call  ;m
:m =jumpz [ t' opJumpZ ] literal call  ;m
:m begin talign there ;m
:m until talign opJumpZ 2/ t, ;m
:m again talign opJump  2/ t, ;m
:m if opJumpZ there 0 t, ;m
:m skip opJump there 0 t, ;m
:m then there 2/ swap t! ;m
:m else skip swap then ;m
:m while if ;m
:m repeat swap again then ;m
:m aft drop skip begin swap ;m
:m next talign opNext 2/ t, ;m

a: reset reset! a;
a: bye halt! a;
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
	1 iAND if
		w iLOAD-C
		low 2/ iRSHIFT
	else
		w iLOAD-C
		low 2/ iAND
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

:m for talign >r begin ;m
:m =>r [ t' >r target.1 -order ] literal call ;m target.1 +order
:m =next [ t' opNext target.1 -order ] literal call ;m

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

a: emit ( ch -- )
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

a: key? ( -- ch -1 | 0 )
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

a: 0= 
	tos iLOAD-C 
	if 
		0 iLOAD-C 
	else 
		set iLOAD-C 
	then 
	tos iSTORE-C 
	a;

a: execute
	tos iLOAD-C
	w iSTORE-C
	{sp} iLOAD
	tos iSTORE-C
	--sp
	w iLOAD-C
	1 iRSHIFT
	{nest} branch 
	a;

a: sp!
	tos iLOAD-C
	{sp} iSTORE-C 
	{sp} iLOAD
	tos iSTORE-C
	--sp
	a;

a: rp!
	tos iLOAD-C
	{rp} iSTORE-C
	{sp} iLOAD
	tos iSTORE-C
	--sp 
	a;

a: sp@
	{sp} iLOAD-C
	w iSTORE-C
	++sp
	tos iLOAD-C
	{sp} iSTORE
	w iLOAD-C
	tos iSTORE-C
	a;

a: rp@
	++sp
	tos iLOAD-C
	{sp} iSTORE
	{rp} iLOAD-C
	tos iSTORE-C
	a;

\ ---- --- ---- ---- ---- no more direct assembly ---- ---- ---- ---- ----

assembler.1 -order

:to reset reset ;t
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
:to emit emit ;t
:to key? key? ;t
:to 0= 0= ;t
:to sp! sp! ;t
:to rp! rp! ;t
:to sp@ sp@ ;t
:to rp@ rp@ ;t
:to execute execute ;t
\ TODO: Create special variables for these.
:t here h lit @ ;t
:t sp0 {sp0} lit @ ;t
:t rp0 {rp0} lit @ ;t
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
:t ] -1 lit state ! ;t
:t [ 0 lit state ! ;t immediate
:t nip swap drop ;t
:t tuck swap over ;t
:t ?dup dup if dup then exit ;t  ( w -- w w | 0 )
:t rot >r swap r> swap ;t        ( w1 w2 w3 -- w2 w3 w1 )
:t -rot rot rot ;t               ( w1 w2 w3 -- w2 w3 w1 )
:t 2drop  drop drop ;t           ( w w -- )
:t 2dup  over over ;t            ( w1 w2 -- w1 w2 w1 w2 )
:t 2>r r> swap >r swap >r >r ;t
:t 2r> r> r> swap r> swap >r ;t
:t +! tuck @ + swap ! ;t ( n a -- )
:t 1+! 1 lit swap +! ;t
:t = xor 0= ;t
:t <> = 0= ;t
:t 0<> 0= 0= ;t
:t 0>= 8000 lit and 0= ;t
:t 0< 8000 lit and 0= 0= ;t
:t negate 1- invert ;t
:t - 1- invert + ;t
:t < - 0< ;t
:t > swap < ;t
:t 0> 0 lit > ;t
:t 2* 1 lit lls ;t
:to 2/ 1 lit lrs ;t
:t cell 2 lit ;t
:t cell+ cell + ;t
:t u< 2dup 0>= swap 0>= xor >r < r> xor ;t
:t aligned dup 1 lit and + ;t
:t align here aligned h lit ! ;t
:t depth sp0 sp@ - 1- ;t
:t c! ( c b -- )
  dup 1 lit and if
    dup >r @ 00FF lit and swap FF lit lls or r> !
  else
    dup >r @ FF00 lit and swap FF lit and or r> !
  then ;t
:t count dup 1+ swap c@ ;t ( b -- b u )
:t , here dup cell+ h lit ! ! ;t ( u -- )
:t allot aligned h lit +! ;t     ( u -- )
:t dnegate invert >r invert 1 lit um+ r> + ;t ( d -- -d )
:t d0= or 0= ;t                         ( d -- f )
:t d+ >r swap >r um+ r> + r> + ;t       ( d d -- d )
:t abs dup 0< if negate then exit ;t    ( n -- n )
:t max 2dup > if drop exit then nip ;t  ( n n -- n )
:t min 2dup < if drop exit then nip ;t  ( n n -- n )
:t +string 1 lit over min rot over + -rot - ;t ( b u -- b u : increment str )
:t pick sp@ + 2* @ ;t
:t catch ( xt -- exception# | 0 \ return addr on stack )
   sp@ >r              ( xt )       \ save data stack pointer
   {handler} lit @ >r  ( xt )       \ and previous handler
   rp@ {handler} lit ! ( xt )       \ set current handler
   execute             ( )          \ execute returns if no throw
   r> {handler} lit !  ( )          \ restore previous handler
   r> drop             ( )          \ discard saved stack ptr
   0 lit ;t            ( 0 )        \ normal completion
:t throw ( ??? exception# -- ??? exception# )
    ?dup if	            ( exc# )     \ 0 throw is no-op
      {handler} lit @ rp!   ( exc# )     \ restore prev return stack
      r> {handler} lit !    ( exc# )     \ restore prev handler
      r> swap >r            ( saved-sp ) \ exc# on return stack
      sp! drop r>           ( exc# )     \ restore stack
    then ;t
:t um* ( u u -- ud )
	0 lit swap ( u1 0 u2 ) $F lit
	for dup um+ >r >r dup um+ r> + r>
		if >r over um+ r> + then
	next rot drop ;t
:t *    um* drop ;t  ( n n -- n )
:t um/mod ( ud u -- ur uq )
  ?dup 0= if -A lit throw then
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
:t /mod  over 0< swap m/mod ;t ( n n -- r q )
:t /    /mod nip ;t            ( n n -- q )
:t key begin key? until ;t
:t type begin dup while swap count emit swap 1- repeat 2drop ;t ( b u -- )
:t fill  swap for swap aft 2dup c! 1+ then next 2drop ;t     ( b u c -- )
:t cmove  for aft >r dup c@ r@ c! 1+ r> 1+ then next 2drop ;t ( b1 b2 u -- )
:t pack$  dup >r 2dup ! 1+ swap cmove r> ;t ( b u a -- a )
:t space bl emit ;t
:t cr =cr lit emit =lf lit emit ;t
:t ok space char o emit char k emit cr ;t
:t tap dup emit over c! 1+ ;t ( bot eot cur c -- bot eot cur )
:t ktap ( bot eot cur c -- bot eot cur )
	dup =cr lit xor if
		=bksp lit xor ( delete? ) if
			bl tap exit
		then
		( ^h : bot eot cur -- bot eot cur )
		>r over r@ < dup if
			=bksp lit dup emit space emit
		then
		r> +
		exit
	then drop nip dup ;t
:t accept ( b u -- b u )
	over + over
	begin
		2dup xor
	while
		key dup bl - $5F lit u< if tap else ktap then
	repeat drop over - ;t
:t query TERMBUF lit =buf lit accept #tib lit ! drop 0 lit >in ! ;t
:t ?depth depth 1- > if -4 lit throw then ;t
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
:t spaces begin dup 0> while space 1- repeat drop ;t ( +n -- )
:t digit 9 lit over < 7 lit and + [char] 0 + ;t         ( u -- c )
:t hold hld @ 1- dup hld ! c! ;t ( c -- )
:t #> 2drop hld @ pad over - ;t  ( w -- b u )
:t #  
   ( 2 lit ?depth )
   0 lit base @  
   ( extract ->) dup >r um/mod r> swap >r um/mod r> rot ( ud ud -- ud u )
   digit hold ;t  ( d -- d )
:t #s begin # 2dup d0= until ;t             ( d -- 0 )
:t <# pad hld ! ;t                          ( -- )
:t sign 0< 0= if exit then [char] - hold ;t ( n -- )
:t u.r >r 0 lit <# #s #>  r> over - spaces type ;t    ( u +n -- : print u right justified by +n )
:t u.  0 lit <# #s #> space type ;t                   ( u -- : print unsigned number )
:t  . dup >r abs 0 lit <# #s r> sign #> space type ;t ( n -- print number )
:t digit? ( c base -- u f )
  >r [char] 0 - 9 lit over <
  if
    7 lit -
    dup $A lit < or
  then dup r> u< ;t
:t >number ( ud b u -- ud b u : convert string to number )
  begin
    2dup 2>r drop c@ base @ digit? ( get next character )
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
  while over c@ [char] . xor
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
:t lit$ do$ ;t               ( -- a : do string NB. )
:t .$ do$ count type ;t      ( -- : print string  )
:m ." .$ $literal ;m
:m $" lit$ $literal ;m
:t .s depth 1- for aft r@ pick . then  next ."  <sp" cr ;t
:t nfa cell+ ;t
:t cfa nfa dup c@ $1F lit and + cell+ 2 lit negate and ;t ( pwd -- cfa )
:t (search-wordlist) ( a wid -- PWD PWD 1|PWD PWD -1|0 a 0: find word in WID )
  swap >r dup
  begin
    dup
  while
    dup nfa count $9F lit ( $1F:word-length + $80:hidden ) and r@ count compare 0=
    if ( found! )
      rdrop
      dup ( immediate? -> ) nfa $40 lit swap @ and 0<>
      1 lit or negate exit
    then
    nip dup @
  repeat
  2drop 0 lit r> 0 lit ;t
:t search-wordlist (search-wordlist) rot drop ;t
:t find last search-wordlist ;t
:t literal =push lit , , ;t immediate
:t (literal) state @ 0= if exit then postpone literal ;t
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
:t eval begin bl word dup c@ while interpret 1 lit ?depth repeat drop ok ;t
:t prequit postpone [ 0 lit >in ! 0 lit ;t
:t ?error ?dup if space . [char] ? emit cr prequit then ;t
:t quit prequit begin query t' eval lit catch ?error again ;t
:t words last begin dup nfa count 1f lit and space type @ ?dup 0= until ;t
:to see bl word find ?found
    cr begin dup @ =unnest lit <> while dup @ u. cell+ repeat @ u. ;t
:to : align here last , {last} lit !
    bl word 
    dup c@ 0= if -A lit throw then
    count + h lit ! align
    =0iGET lit , =nest lit , ]  666 lit  ;t
:to ; postpone [ 666 lit <> if -16 lit throw then  =unnest lit , ;t immediate
:to begin align here ;t immediate compile-only
:to until align =jumpz lit , 1 lit lrs , ;t immediate compile-only
:to again align =jump  lit , 1 lit lrs , ;t immediate compile-only
:to if align =jumpz lit , here 0 lit , ;t immediate compile-only
\ :t skip =jump lit , 0 lit , ;t
\ :to else skip swap topost then ;t immediate compile-only
:to then here 1 lit lrs swap ! ;t immediate compile-only
:to for align =>r lit , here ;t immediate compile-only
:to next align =next lit , 1 lit lrs , ;t immediate compile-only
\ :to aft drop skip begin swap ;t
\ :to while if ;t
\ :to repeat swap again then ;t
\ :to next talign opNext 2/ t, ;t
:to ' bl word find ?found cfa state @ if (literal) then ;t immediate
:t compile r> dup 1 lit lls @ , 1+ >r ;t compile-only
:to ." compile .$ [char] " word count + h lit ! align ;t immediate compile-only
:to $" compile lit$ [char] " word count + h lit ! align ;t immediate compile-only  \ "
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
:t cold 
	there 2/ <cold> t! \ program entry point set here
	hex ." eForth v1.1.0" ok quit bye ;t

there h t!
atlast {last} t!
save-hex bit.hex
save-target bit.bin
.stat
.end
.( DONE ) cr
bye

