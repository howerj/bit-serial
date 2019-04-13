/* Bit-Serial CPU simulator
 * LICENSE: MIT
 * AUTHOR:  Richard James Howe
 * EMAIL:   howe.r.j.89@gmail.com
 * GIT:     https://github.com/howerj/bit-serial */
#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#define CONFIG_TRACER_ON (1)
#define MSIZE            (4096u)
typedef uint16_t mw_t; /* machine word */
typedef struct { mw_t pc, acc, m[MSIZE]; } bcpu_t;

static inline int trace(bcpu_t *b, FILE *tracer, unsigned cycles, const mw_t pc, const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	if (!tracer)
		return 0;
	static const char *cmds[] = { 
		"nop    ", "halt   ", "jump   ", "jumpz  ", 
		"and    ", "or     ", "xor    ", "invert ",
		"load   ", "store  ", "literal", "11?    ",
		"add    ", "less   ", "14?    ", "15?    "
	};
	assert(cmd < (sizeof(cmds)/sizeof(cmds[0])));
	return fprintf(tracer, "%4x: %4x %s %4x %4x\n", cycles, (unsigned)pc, cmds[cmd], (unsigned)acc, (unsigned)op1);
}

static int bcpu(bcpu_t *b, FILE *in, FILE *out, FILE *tracer, const unsigned cycles) {
	assert(b);
	assert(in);
	assert(out);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc;
	const unsigned forever = cycles == 0;
       	unsigned count = 0;
	for (; count < cycles || forever; count++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		if (CONFIG_TRACER_ON)
			trace(b, tracer, count, pc, acc, op1, cmd);
		pc++;
		switch (cmd) {
		case 0x0:                        break; /* NOP     */
		case 0x1: r = 0;             goto halt; /* HALT    */
		case 0x2: pc = op1;              break; /* JUMP    */
		case 0x3: if (!(acc)) pc = op1;  break; /* JUMPZ   */

		case 0x4: acc &= op1;            break; /* AND     */
		case 0x5: acc |= op1;            break; /* OR      */
		case 0x6: acc ^= op1;            break; /* XOR     */
		case 0x7: acc = ~acc;            break; /* INVERT  */

		case 0x8: acc = m[op1 % MSIZE];  break; /* LOAD    */
		case 0x9: m[op1 % MSIZE] = acc;  break; /* STORE   */
		case 0xA: acc = op1;             break; /* LITERAL */
		/*   0xB: Reserved for memory operations           */

		case 0xC: acc += op1;            break; /* ADD      */
		case 0xD: acc  = acc < op1;      break; /* LESS     */
		/*   0xE: Reserved for arithmetic operations        */
		/*   0xF: Reserved for arithmetic operations        */
		
		default: r = -1; goto halt;
		}
	}
halt:
	b->pc  = pc;
	b->acc = acc;
	return r;
}

int main(int argc, char **argv) {
	static bcpu_t b = { 0, 0, { 0 } };
	if (argc != 2) {
		fprintf(stderr, "usage: %s file\n", argv[0]);
		return -1;
	}
	FILE *program = fopen(argv[1], "rb");
	if (!program) {
		fprintf(stderr, "could not open file for reading: %s\n", argv[1]);
		return -2;
	}
	for (size_t i = 0; i < MSIZE; i++) {
		int pc = 0;
		if (fscanf(program, "%x", &pc) != 1)
			break;
		b.m[i] = pc;
	}
	fclose(program);
	return bcpu(&b, stdin, stdout, stderr, 0x1000);
}
