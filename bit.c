/* bitwise CPU simulator */
#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#define MSIZE (16384u)

typedef struct {
	uint16_t pc, acc, carry, m[MSIZE];
} bcpu_t;

static int bcpu(bcpu_t *b, FILE *in, FILE *out) {
	assert(b);
	assert(in);
	assert(out);
	for (;;) {
		const uint16_t instr = b->m[b->pc++ % MSIZE];
		switch (instr & 0xFu) { 
		/* HALT, +, &, |, ^, ~, LOAD, STORE, JUMP */
		case  0: return 0;                               /* HALT */
		case  1: {
			const int always   = (instr & 0x10);
			const int zero     = (instr & 0x20) && !(b->acc);
			const int carry    = (instr & 0x40) && b->carry;
			const int negative = (instr & 0x80) && (b->acc & 0x8000u);
			if (always || zero || negative || carry)
				b->pc = b->m[b->pc % MSIZE];
			else
				b->pc++;
		}
		break;
		case  2: b->acc += b->m[b->pc++ % MSIZE]; break; /* ADD     */
		case  3: b->acc &= b->m[b->pc++ % MSIZE]; break; /* AND     */
		case  4: b->acc |= b->m[b->pc++ % MSIZE]; break; /* OR      */
		case  5: b->acc ^= b->m[b->pc++ % MSIZE]; break; /* XOR     */
		case  6: b->acc = b->m[b->pc++ % MSIZE];  break; /* LITERAL */
		case  7: b->m[b->pc++ % MSIZE] = b->acc;  break; /* LOAD    */
		case  8: b->acc = b->m[b->pc++ % MSIZE];  break; /* STORE   */
		case  9: b->acc = ~b->acc;                break; /* INVERT  */
		case 10: b->carry = 0;                    break; /* CLEAR   */
		case 11: b->acc = fgetc(in);              break;
		case 12: fputc(b->acc, out);              break;
		default: return -1;
		}
	}
	return 0;
}

int main(int argc, char **argv) {
	static bcpu_t b = { 0, 0, 0, { 0 } };

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
	return bcpu(&b, stdin, stdout);
}
