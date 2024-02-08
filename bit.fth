\ Author: Richard James Howe
\ Email: howe.r.j.89@gmail.com
\ Repo: https://github.com/howerj/bit-serial
\ License: MIT
\
\ Cross Compiler and eForth interpreter for the bit-serial CPU 
\ available at:
\
\   <https://github.com/howerj/bit-serial>
\
\ This implements a Direct Threaded Code virtual machine on 
\ which we can build a Forth interpreter.
\
\ References:
\
\ - <https://en.wikipedia.org/wiki/Threaded_code>
\ - <https://github.com/howerj/embed>
\ - <https://github.com/howerj/forth-cpu>
\ - <https://github.com/samawati/j1eforth>
\ - <https://www.bradrodriguez.com/papers/>
\ - <https://github.com/howerj/subleq>
\ - 8086 eForth 1.0 by Bill Muench and C. H. Ting, 1990
\
\ For a more feature complete eForth see:
\
\ - <https://github.com/howerj/subleq>
\
\ Which targets an even more constrained system but contains
\ a more featureful Forth (it has USER variables, multitasking,
\ a system vocabulary, image checksum, optional components such 
\ as floating points and memory allocation and lots of 
\ documentation, a better decompiler, a "self-interpreter", a
\ block editor and block system, sleep, more control words,
\ and much more) and is self-hosting.
\
\ The cross compiler has been tested and works with gforth 
\ versions 0.7.0 and 0.7.3. An already compiled image (called 
\ 'bit.hex') should be available if you do not have gforth 
\ installed.
\
\ The threading model could be changed to save on space.
\

only forth also definitions hex

wordlist constant meta.1
wordlist constant target.1
wordlist constant assembler.1
wordlist constant target.only.1

: (order) ( u wid*n n -- wid*n u n )
   dup if
    1- swap >r recurse over r@ xor if
     1+ r> -rot exit then r> drop then ;
: -order ( wid -- ) get-order (order) nip set-order ;
: +order ( wid -- ) 
  dup >r -order get-order r> swap 1+ set-order ;

meta.1 +order also definitions

   2 constant =cell
4000 constant size ( 16384 bytes, 8192 cells )
2000 constant =end ( 8192 bytes, leaving half for DP-BRAM )
  40 constant =stksz
  60 constant =buf
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

: :m meta.1 +order also definitions : ;
: ;m postpone ; ; immediate
:m there tdp @ ;m
:m tc! tflash + c! ;m
:m tc@ tflash + c@ ;m
:m t! over ff and over tc! swap 8 rshift swap 1+ tc! ;m
:m t@ dup tc@ swap 1+ tc@ 8 lshift or ;m
:m talign there 1 and tdp +! ;m
:m tc, there tc! 1 tdp +! ;m
:m t, there t! 2 tdp +! ;m
:m $literal [char] " word 
  count dup tc, 0 ?do count tc, loop drop talign ;m
:m tallot tdp +! ;m
:m thead
  talign
  there tlast @ t, tlast !
  parse-word dup tc, 0 ?do count tc, loop drop talign ;m
:m hex# ( u -- addr len )  
  0 <# base @ >r hex =lf hold # # # # r> base ! #> ;m
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
:m .end only forth also definitions decimal ;m
:m atlast tlast @ ;m
:m tvar   get-current >r meta.1 set-current 
          create r> set-current there , t, does> @ ;m
:m label: get-current >r meta.1 set-current 
          create r> set-current there ,    does> @ ;m
:m tdown =cell negate and ;m
:m tnfa =cell + ;m ( pwd -- nfa : move to name field address )
:m tcfa tnfa dup c@ $1F and + =cell + tdown ;m ( pwd -- cfa )
:m compile-only tlast @ tnfa t@ $20 or tlast @ tnfa t! ;m
:m immediate    tlast @ tnfa t@ $40 or tlast @ tnfa t! ;m
:m t' ' >body @ ;m
:m call 2/ C000 or ;m
:m t2/ 2/ ;m

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
 8 constant flgR
10 constant flgHlt

: flags? 1 iGET ;
: flags! 1 iSET ;
: halt! flgHlt iLITERAL flags! ;
: branch 2/ iJUMP ;
: ?branch 2/ iJUMPZ ;
: zero? flags? 2 iAND ;
:m postpone t' branch ;m

assembler.1 +order also definitions
: begin there ;
: until ?branch ;
: again branch ;
: if there 0 ?branch ;
: mark there 0 branch ;
: then begin 2/ over t@ or swap t! ;
: else mark swap then ;
: while if swap ;
: repeat branch then ;
assembler.1 -order
meta.1 +order also definitions

\ --- ---- ---- ---- image generation   ---- ---- ---- ---- --- 

0 t,  \ must be 0 ('0 iOR'  works in indirect or direct mode )
1 t,  \ must be 1 ('1 iADD' works in indirect or direct mode )
2 t,  \ must be 2 ('2 iADD' works in indirect or direct mode )
label: entry ( previous three instructions are irrelevant )
0 t,  \ entry point to virtual machine

FFFF tvar set       \ all bits set, -1
  FF tvar low       \ lowest 8-bits set
   0 tvar <cold>    \ entry point of virtual machine, set later

   0 tvar ip        \ instruction pointer
   0 tvar t         \ temporary register
   0 tvar tos       \ top of stack
   0 tvar h         \ dictionary pointer
   0 tvar {state}   \ compiler state
   0 tvar {hld}     \ hold space pointer
   0 tvar {base}    \ input/output radix, default = 16
   0 tvar {dpl}     \ number of places after fraction
   0 tvar {in}      \ position in query string
   0 tvar {handler} \ throw/catch handler
   0 tvar {last}    \ last defined word
   0 tvar #tib      \ terminal input buffer

 =end              dup tvar {sp0} tvar {sp} \ grows downwards
 =end =stksz 2* -  dup tvar {rp0} tvar {rp} \ grows upwards
 =end =stksz 2* - =buf - constant TERMBUF \ pad buffer space

TERMBUF =buf + constant =tbufend

: vcell 1 ( cell '1' should contain '1' ) ;
: -vcell set 2/ ;
: --sp {sp} iLOAD-C  vcell iADD {sp} iSTORE-C ;
: ++sp {sp} iLOAD-C -vcell iADD {sp} iSTORE-C ;
: --rp {rp} iLOAD-C -vcell iADD {rp} iSTORE-C ;
: ++rp {rp} iLOAD-C  vcell iADD {rp} iSTORE-C ;

\ --- ---- ---- ---- Forth VM ---- ---- ---- ---- ---- ---- --- 

label: start
  start call entry t!
  {sp0} iLOAD-C {sp} iSTORE-C
  {rp0} iLOAD-C {rp} iSTORE-C
  <cold> iLOAD-C
  ip iSTORE-C
  \ -- fall-through --
label: vm ( The Forth virtual machine )
  ip iLOAD-C
  t iSTORE-C
  ( ip iLOAD-C already in accm. ) 1 iADD ip iSTORE-C
  t iLOAD-C
  0 iSET \ jump to next token

:m a: ( "name" -- : assembly only routine, no header )
  CAFED00D
  target.1 +order also definitions
  create talign there ,
  assembler.1 +order
  does> @ branch ;m
:m (a); CAFED00D <> if abort" unstructured" then 
  assembler.1 -order ;m
:m a; (a); vm branch ;m

a: execute ( xt -- : execute an execution token! )
  tos iLOAD-C
  t iSTORE-C
  {sp} iLOAD
  tos iSTORE-C
  --sp
  t iLOAD-C
  1 iRSHIFT
  (a); ( fall-through to {nest} )
( fn call: accumulator must contain '0 iGET' prior to call )
label: {nest} 
  t iSTORE-C ( store '0 iGET' into working pointer )
  ++rp
  ip iLOAD-C
  {rp} iSTORE
  t iLOAD-C
  2 iADD
  ip iSTORE-C
  vm branch

a: exit ( -- : exit from current function ) 
label: {unnest} ( return from function call )
  {rp} iLOAD
  t iSTORE-C
  --rp
  t iLOAD-C
  ip iSTORE-C
  vm branch
  (a); 

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
  get-current >r target.only.1 set-current create r> 
  set-current
  there ,
  nest CAFEBABE
  does> @ branch ;m

:m ;t CAFEBABE <> if abort" unstructured" then 
  talign unnest target.only.1 -order ;


a: opPush ( pushes next value in instr stream to the stack )
  ++sp
  tos iLOAD-C
  {sp} iSTORE
  ip iLOAD-C
  t iSTORE-C
  t iLOAD
  tos iSTORE-C
label: IncIp ip iLOAD-C 1 iADD ip iSTORE-C vm branch
  (a);

a: opJumpZ
  tos iLOAD-C
  t iSTORE-C
  {sp} iLOAD
  tos iSTORE-C
  --sp
  t iLOAD-C
  if
    IncIp branch
  then
  (a); ( fall-through to opJump )
a: opJump ( jump to next value in instruction stream )
label: Jump ( A few instructions jump here to save space )
  ip iLOAD
  ip iSTORE-C
  a;

a: opNext
  {rp} iLOAD
  if
    set 2/ iADD
    {rp} iSTORE
    Jump branch
  then
  --rp
  IncIp branch
  (a);

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
:m mark opJump there 0 t, ;m
:m then there 2/ swap t! ;m
:m else mark swap then ;m
:m while if ;m
:m repeat swap again then ;m
:m aft drop mark begin swap ;m
:m next talign opNext 2/ t, ;m

a: bye halt! (a);   ( -- : bye bye! )

a: and ( u u -- u : bit wise AND )
  {sp} iLOAD
  tos 2/ iAND
label: decSp tos iSTORE-C --sp vm branch
  (a);

a: or ( u u -- u : bit wise OR )
  {sp} iLOAD
  tos 2/ iOR
  decSp branch
  (a);

a: xor ( u u -- u : bit wise XOR )
  {sp} iLOAD
  tos 2/ iXOR
  decSp branch
  (a);

a: lls ( u shift -- u : shift left by number of bits set )
  {sp} iLOAD
  tos 2/ iLSHIFT
  decSp branch
  (a);

a: lrs ( u shift -- u : shift right by number of bits set )
  {sp} iLOAD
  tos 2/ iRSHIFT
  decSp branch
  (a);

a: um+ ( u u -- u f : Add with carry )
  {sp} iLOAD
  tos 2/ iADD
  {sp} iSTORE
  flags?
  flgCy iAND
  tos iSTORE-C
  a;

a: @ ( a -- u : load a memory address )
  tos iLOAD-C
  1 iRSHIFT
  tos iSTORE-C
  tos iLOAD
  tos iSTORE-C
  a;

a: ! ( u a -- store a cell at a memory address )
  tos iLOAD-C
  1 iRSHIFT
  t iSTORE-C
  {sp} iLOAD
  t iSTORE
  --sp
  {sp} iLOAD
  decSp branch
  (a);

a: dup ( u -- u u : duplicate item on top of stack )
  ++sp
  tos iLOAD-C
  {sp} iSTORE
  a;

a: drop ( u -- : drop it like it's hot )
  {sp} iLOAD
  decSp branch
  (a);

a: swap ( u1 u2 -- u2 u1 : swap top two stack items )
  {sp} iLOAD
  t iSTORE-C
  tos iLOAD-C
  {sp} iSTORE
  t iLOAD-C
  tos iSTORE-C
  a;

a: >r ( u -- , R: -- u ) 
  ++rp
  tos iLOAD-C
  {rp} iSTORE
  {sp} iLOAD
  decSp branch
  (a);

:m for talign >r begin ;m
:m =>r [ t' >r ] literal call ;m
:m =next [ t' opNext ] literal call ;m

a: r>
  ++sp
  tos iLOAD-C
  {sp} iSTORE
  {rp} iLOAD
  tos iSTORE-C
  (a); ( fall-through to rdrop )
a: rdrop ( --, R: u -- : drop top item on return stack )
  --rp 
  a;
 
a: r@ ( -- u, R: u -- u )
  ++sp
  tos iLOAD-C
  {sp} iSTORE
  {rp} iLOAD
  tos iSTORE-C
  a;

a: sp! ( ??? u -- ??? : set stack depth )
  tos iLOAD-C
  {sp} iSTORE-C
  {sp} iLOAD
  tos iSTORE-C
  a;

a: rp! ( u -- , R: ??? --- ??? : set return stack depth )
  tos iLOAD-C
  {rp} iSTORE-C
  {sp} iLOAD
  decSp branch
  (a);

\ --- ---- ---- ---- no more direct assembly ---- ---- ---- --- 

assembler.1 -order

:m : :t ;
:m ; ;t ;
:to bye bye ;
:to and and ;
:to or or ;
:to xor xor ;
:to um+ um+ ;
:to @ @ ;
:to ! ! ;
:to dup dup ;
:to drop drop ;
:to swap swap ;
:to execute execute ;
:ht #0   0 lit ; ( --  0 : push  0 onto variable stack )
:ht #1   1 lit ; ( --  1 : push  1 onto variable stack )
:ht #-1 -1 lit ; ( -- -1 : push -1 onto variable stack )
: + um+ drop ;
: 1- #-1 + ;
: 1+ #1 + ;
:ht sp@ {sp} lit @ 1+ ;
:ht rp@ {rp} lit @ 1- ;
: 0= if #0 exit then #-1 ;
: invert #-1 xor ;
: emit ( ch -- )
   begin 8002 lit @ 1000 lit and 0= until
   FF lit and 2000 lit or 8002 lit ! ;
: key? ( -- ch -1 | 0 )
   8002 lit @ 100 lit and if #0 exit then
   400 lit 8002 lit ! 8002 lit @ FF lit and #-1 ;
\ TODO: `h lit` -> `:ht #h h lit ;`
: here h lit @ ;     ( -- u )
: base {base} lit ;  ( -- a : base controls I/O radix )
: dpl {dpl} lit ;    ( -- a : push address of 'dpl' )
: hld {hld} lit ;    ( -- a : push address of 'hld' )
: bl 20 lit ;        ( -- space : push a space )
: >in {in} lit ;     ( -- b : push pointer to TIB position )
: hex  10 lit base ! ; ( -- : switch to hex I/O radix )
: source TERMBUF lit #tib lit @ ; ( -- b u )
: last {last} lit @ ;   ( -- : last defined word )
: state {state} lit ;   ( -- a : compilation state variable )
: ] #-1 state ! ;       ( -- : turn compile mode on )
: [ #0 state ! ; immediate ( -- : turn compile mode off )
: over swap dup >r swap r> ; ( u1 u2 -- u1 u2 u1 )
: nip swap drop ;       ( u1 u2 -- u2 )
: tuck swap over ;      ( u1 u2 -- u2 u1 u2 )
: ?dup dup if dup then ;   ( u -- u u | 0 : dup if not zero )
: rot >r swap r> swap ; ( u1 u2 u3 -- u2 u3 u1 )
: 2drop drop drop ;     ( u u -- : drop two numbers )
: 2dup  over over ;     ( u1 u2 -- u1 u2 u1 u2 )
: +! tuck @ + swap ! ;  ( n a -- : incr val at addr by 'n' )
: negate 1- invert ;    ( n -- n : negate [twos compliment] )
: - negate + ;          ( u u -- u : subtract )
: = xor 0= ;            ( u u -- f : equality )
: <> = 0= ;             ( u u -- f : inequality )
: 0>= 8000 lit and 0= ; ( n -- f : greater or equal to zero )
: 0< 0>= 0= ;           ( n -- f : less than zero )
: < - 0< ;              ( n n -- f : signed less than )
: > swap < ;            ( n n -- f : signed greater than )
: 0> #0 > ;             ( n -- f : greater than zero )
: u< 2dup 0>= swap 0>= xor >r < r> xor ; ( u u -- f : )
: 2* #1 lls ;           ( u -- u : multiply by two )
: 2/ #1 lrs ;           ( u -- u : divide by two )
: cell 2 lit ;          ( -- u : size of memory cell )
: cell+ cell + ; ( a -- a : increment address to next cell )
: pick sp@ + 2* @ ;     ( ??? u -- ??? u u : )
: aligned dup #1 and + ;       ( b -- u : align a pointer )
: align here aligned h lit ! ; ( -- : align dictionary ptr )
: depth {sp0} lit @ sp@ - 1- ; ( -- u : var stack depth )
: c@ dup @ swap #1 and if FF lit lrs then FF lit and ;
: c! ( c b -- : store character at address )
  dup dup >r #1 and if
    @ 00FF lit and swap FF lit lls
  else
    @ FF00 lit and swap FF lit and
  then or r> ! ;
: count dup 1+ swap c@ ; ( b -- b c )
: allot aligned h lit +! ;    ( u -- )
: , align here ! cell allot ; ( u -- )
: abs dup 0< if negate then ; ( n -- u )
: mux dup >r and swap r> invert and or ; ( u1 u2 sel -- u )
: max 2dup < mux ;  ( n n -- n : maximum of two numbers )
: min 2dup > mux ;  ( n n -- n : minimum of two numbers )
: +string #1 over min rot over + rot rot - ; ( b u -- b u )
: catch ( xt -- exception# | 0 \ return addr on stack )
   sp@ >r              ( xt )   \ save data stack pointer
   {handler} lit @ >r  ( xt )   \ and previous handler
   rp@ {handler} lit ! ( xt )   \ set current handler
   execute             ( )      \ execute returns if no throw
   r> {handler} lit !  ( )      \ restore previous handler
   rdrop               ( )      \ discard saved stack ptr
   #0 ;               ( 0 )    \ normal completion
: throw ( ??? exception# -- ??? exception# )
    ?dup if              ( exc# )  \ 0 throw is no-op
      {handler} lit @ rp! ( exc# ) \ restore prev return stack
      r> {handler} lit !  ( exc# ) \ restore prev handler
      r> swap >r          ( saved-sp ) \ exc# on return stack
      sp! drop r>         ( exc# ) \ restore stack
    then ;
: um* ( u u -- ud : double cell width multiply )
  #0 swap ( u1 0 u2 ) $F lit
  for dup um+ >r >r dup um+ r> + r>
    if >r over um+ r> + then
  next rot drop ;
: um/mod ( ud u -- ur uq : unsigned double cell div/mod )
  ?dup 0= -A lit and throw 
  2dup u<
  if negate $F lit
    for >r dup um+ >r >r dup um+ r> + dup
      r> r@ swap >r um+ r> or
      if >r drop 1+ r> else drop then r>
    next
    drop swap exit
  then 2drop drop #-1 dup ;
: key begin key? until ; ( c -- : get a character from UART )
: type begin dup while swap count emit swap 1- repeat 2drop ;
: cmove for aft >r dup c@ r@ c! 1+ r> 1+ then next 2drop ;
:ht do$ r> r> 2* dup count + aligned 2/ >r swap >r ; ( -- a : )
:ht ($) do$ ;            ( -- a : do string NB. )
:ht .$ do$ count type ;  ( -- )
:m ." .$ $literal ;m
:m $" ($) $literal ;m
: space bl emit ;               ( -- : print space )
: cr .$ 2 tc, =cr tc, =lf tc, ; ( -- : print new line )
:ht ktap ( bot eot cur c -- bot eot cur )
  dup dup =cr lit <> >r  =lf lit <> r> and if \ Not End Line?
    dup =bksp lit <> >r =del lit <> r> and if \ Not Del Char?
      bl 
      ( tap: ) 
        dup emit over c! 1+ ( bot eot cur c -- bot eot cur )
      exit
    then
    >r over r@ < dup if
      =bksp lit dup emit space emit
    then
    r> +
    exit
  then drop nip dup ;
: accept ( b u -- b u : read in a line of user input )
  over + over
  begin
    2dup xor
  while
    key dup bl - $5F lit u< if 
      ( tap: ) dup emit over c! 1+ 
    else ktap then
  repeat drop over - ;
: query ( -- : get line)
   TERMBUF lit =buf lit accept #tib lit ! drop #0 >in ! ; 
: ?depth depth > -4 lit and throw ; ( u -- )
: -trailing ( b u -- b u : remove trailing spaces )
  for
    aft bl over r@ + c@ <
      if r> 1+ exit then
    then
  next #0 ;
:ht look ( b u c xt -- b u : skip until *xt* test succeeds )
  swap >r rot rot
  begin
    dup
  while
    over c@ r@ - r@ bl = 4 lit pick execute
    if rdrop rot drop exit then
    +string
  repeat rdrop rot drop ;
:ht no-match if 0> exit then 0= 0= ; ( c1 c2 -- t )
:ht match no-match invert ;          ( c1 c2 -- t )
: parse ( c -- b u ; <string> )
  >r source drop >in @ + #tib lit @ >in @ - r@
  >r over r> swap >r >r
  r@ t' no-match lit look 2dup
  ( b u c -- b u delta: )
  r> t' match lit look swap r> - >r - r> 1+ 
  >in +!
  r> bl = if -trailing then #0 max ;
: spaces begin dup 0> while space 1- repeat drop ; ( +n -- )
: hold #-1 hld +! hld @ c! ; ( c -- : save char to hold )
: #> 2drop hld @ =tbufend lit over - ;  ( u -- b u )
: #  ( d -- d : add next character in number to hold space )
   2 lit ?depth
   #0 base @
   ( extract: ) 
     dup >r um/mod r> swap >r um/mod r> rot ( ud ud -- ud u )
   ( digit: ) 
     9 lit over < 7 lit and + [char] 0 + ( u -- c )
   hold ;
: #s begin # 2dup ( d0= -> ) or 0= until ;       ( d -- 0 )
: <# =tbufend lit hld ! ;                        ( -- )
: sign 0< if [char] - hold then ;                ( n -- )
: u.r >r #0 <# #s #>  r> over - spaces type ;    ( u +n -- )
: u. space #0 u.r ;                              ( u -- )
: . dup >r abs #0 <# #s r> sign #> space type ;  ( n -- )
: >number ( ud b u -- ud b u : convert string to number )
  begin
    2dup >r >r drop c@ base @        ( get next character )
    ( digit? -> ) >r [char] 0 - 9 lit over <
    if 7 lit - dup $A lit < or then dup r> u< ( c base -- u f )
    0= if                   ( d char )
      drop                  ( d char -- d )
      r> r>                 ( restore string )
      exit                  ( ..exit )
    then                    ( d char )
    swap base @ um* drop rot base @ um* 
    ( d+ -> ) >r swap >r um+ r> + r> + ( accumulate digit )
    r> r>                   ( restore string )
    +string dup 0=          ( advance string and test for end )
  until ;
: number? ( a u -- d -1 | a u 0 : string to a number )
  #-1 dpl !
  base @ >r
  over c@ [char] - = dup >r if     +string then
  over c@ [char] $ =        if hex +string then
  >r >r #0 dup r> r>
  begin
    >number dup
  while over c@ [char] . xor
    if rot drop rot r> 2drop #0 r> base ! exit then
    1- dpl ! 1+ dpl @
  repeat 
  2drop r> if 
    ( dnegate -> ) invert >r invert #1 um+ r> + 
  then r> base ! #-1 ;
: compare ( a1 u1 a2 u2 -- n : string equality )
  rot
  over - ?dup if >r 2drop r> nip exit then
  for ( a1 a2 )
    aft
      count rot count rot - ?dup
      if rdrop nip nip exit then
    then
  next 2drop #0 ;
:to .s depth  for aft r@ pick . then next ;
: nfa cell+ ; ( pwd -- nfa : move word ptr to name field )
: cfa nfa dup c@ $1F lit and + cell+ cell negate and ; 
: (find) ( a wid -- PWD PWD 1|PWD PWD -1|0 a 0 )
  swap >r dup
  begin
    dup
  while
    dup nfa count $9F lit ( $1F:word-length + $80:hidden ) 
    and r@ count compare 0=
    if ( found! )
      rdrop
      dup ( immediate? -> ) nfa $40 lit swap @ and 0= 0=
      #1 or negate exit
    then
    nip dup @
  repeat
  2drop #0 r> #0 ;
: find last (find) rot drop ;  ( "name" -- b )
: literal state @ if =push lit , , then ; immediate ( u -- )
: compile, 2/ align C000 lit or , ;                 ( xt -- )
:ht ?found if exit then ( u f -- )
   space count type [char] ? emit cr -D lit throw ; 
: interpret                                          ( b -- )
  find ?dup if
    state @
    if
      0> if cfa execute exit then \ <- immediate word executed
      cfa compile, exit \ <- compiling words are...compiled.
    then
    drop
    dup nfa c@ 20 lit and if -E lit throw then ( <- ?compile )
    cfa execute exit  \ <- if its not, execute it, then exit 
  then
  \ not a word
  dup >r count number? if rdrop \ it is a number!
    dpl @ 0< if \ <- dpl will be -1 if it is a single cell num
      drop \ drop high cell from 'number?' for single cell
    else   \ <- dpl is not -1, it is a double cell number
       state @ if swap then
       postpone literal \ if double, execute 'literal' twice
    then
    postpone literal exit
  then
  r> #0 ?found \ Could vector ?found
  ;
: word parse here dup >r 2dup ! 1+ swap cmove r> ; ( c -- b )
: words last begin 
   dup nfa count 1f lit and space type @ ?dup 0= until ;
: see bl word find ?found cr 
  begin 
    dup @ =unnest lit <> 
  while dup @ u. cell+ repeat @ u. ;
:to : align here last , {last} lit ! ( "name" -- )
  bl word
  dup c@ 0= -A lit and throw
  count + h lit ! align
  =0iGET lit , =nest lit , ] BABE lit ;
:to ; postpone [ 
   BABE lit <> -16 lit and throw 
   =unnest lit , ; immediate compile-only
:to begin align here ; immediate compile-only
:to until =jumpz lit , 2/ , ; immediate compile-only
:to again =jump  lit , 2/ , ; immediate compile-only
:to if =jumpz lit , here #0 , ; immediate compile-only
:to then here 2/ swap ! ; immediate compile-only
:to for =>r lit , here ; immediate compile-only
:to next =next lit , 2/ , ; immediate compile-only
:to ' bl word find ?found cfa literal ; immediate
: compile r> dup 2* @ , 1+ >r ; compile-only
:to >r compile >r ; immediate compile-only
:to r> compile r> ; immediate compile-only
:to r@ compile r@ ; immediate compile-only 
:to exit compile exit ; immediate compile-only
:ht pack word count + h lit ! align ;
:to ." compile .$  [char] " pack ; immediate compile-only
:to $" compile ($) [char] " pack ; immediate compile-only
:to ( [char] ) parse 2drop ; immediate
:to \ source drop @ >in ! ; immediate
:to immediate last nfa @ $40 lit or last nfa ! ;
: dump begin over c@ u. +string ?dup 0= until drop ;
: eval begin bl word dup c@ while 
   interpret #1 ?depth repeat drop ."  ok" cr ;
:ht ini hex postpone [ #0 >in ! #-1 dpl ! ; ( -- )
: quit ( -- : interpreter loop [and more] )
  there t2/ <cold> t! \ program entry point set here
  ." eForth 3.2" cr
  ini 
  begin
    query t' eval lit catch
    ( ?error -> ) ?dup if
      space . [char] ? emit cr ini
    then again ;

\ --- ---- ---- ---- implementation finished ---- ---- ---- ---

there h t!
atlast {last} t!
save-hex bit.hex
save-target bit.bin
.stat
.end
.( DONE ) cr
bye

