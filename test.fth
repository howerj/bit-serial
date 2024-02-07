\ ./bit bit.hex < test.fth
\ Basic Forth Test Suite 

2 2 + . cr


: hello cr ." HELLO, WORLD!" ;

hello

see hello

' hello execute

-2 throw

cr bye
