CC=gcc
CFLAGS=-Wall -Wextra -std=c99 -O2
.PHONY: all run simulate viewer clean

all: bit simulate

run: bit bit.hex
	./bit -r bit.hex

simulate: tb.ghw

viewer: tb.ghw
	gtkwave -f $< &> /dev/null&

clean:
	rm -fv *.cf *.o *.ghw *.hex tb bit

%.hex: %.asm bit
	./bit -a $< $@

bit: bit.c
	${CC} ${CFLAGS} $< -o $@

%.o: %.vhd
	ghdl -a -g $<

top.o: mem.o bit.o

tb.o: tb.vhd bit.o mem.o top.o

tb: tb.o bit.o mem.o top.o
	ghdl -e tb

tb.ghw: tb bit.hex
	ghdl -r $< --wave=$<.ghw --max-stack-alloc=16384 --ieee-asserts=disable


