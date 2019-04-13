CC=gcc
CFLAGS=-Wall -Wextra -std=c99 -O2
.PHONY: all run simulate clean

all: bit tb

run: bit
	./bit

simulate: tb
	./tb

bit: bit.c
	${CC} ${CFLAGS} $< -o $@

tb.o: tb.vhd
	ghdl -a -g $<

bit.o: bit.vhd
	ghdl -a -g $<

tb: tb.o bit.o
	ghdl -e tb

clean:
	rm -fv *.cf *.o tb bit
