\ ./bit bit.hex < test.fth
\ Basic Forth Test Suite 

2 2 + . cr


: hello cr ." HELLO, WORLD!" ;

hello

see hello

' hello execute

-2 throw ( should throw an error )

cr words

: z1 if A5F0 u. cr exit then FA50 u. ;

0 z1
1 z1

cr bye
