/* Bit-Serial CPU simulator
 * LICENSE: MIT
 * AUTHOR:  Richard James Howe
 * EMAIL:   howe.r.j.89@gmail.com
 * GIT:     https://github.com/howerj/bit-serial */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <stdarg.h>
#include <limits.h>

#define MSIZE            (4096u)
#define MAX_VARS         (256u)
#define NELEM(X)         (sizeof(X)/sizeof(X[0]))
#define MAX_FILE         (128*1024)
#define MAX_NAME         (32)

typedef uint16_t mw_t; /* machine word */
typedef struct { 
	mw_t pc, acc, flg, m[MSIZE]; 
	/* io */ 
	FILE *in, *out, *trace; mw_t ch, leds, switches; 
	/* options */
	int rheader, dec; 
} bcpu_t;
enum { fCy, fZ, fNg, fPAR, fROT, fR, fIND, fHLT, };

static void die(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	(void)vfprintf(stderr, fmt, ap);
	(void)fputc('\n', stderr);
	(void)fflush(stderr);
	va_end(ap);
	exit(EXIT_FAILURE);
}

static int debug(bcpu_t *b, const char *fmt, ...) {
	assert(b);
	assert(fmt);
	if (!(b->trace))
		return 0;
	va_list ap;
	va_start(ap, fmt);
	const int r1 = vfprintf(b->trace, fmt, ap);
	const int r2 = fputc('\n', b->trace);
	const int r3 = fflush(b->trace);
	va_end(ap);
	return r1 < 0 || r2 < 0 || r3 < 0 ? -1 : r1 + 1;
}

static int trace(bcpu_t *b, 
		unsigned cycles, const mw_t pc, const mw_t flg, 
		const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	if (!(b->trace))
		return 0;
	static const char *commands[] = { 
		"or     ", "and    ", "xor    ", "add    ",  
		"lshift ", "rshift ", "load   ", "store  ",
		"load-c ", "store-c", "literal", "unused ",
		"jump   ", "jumpz  ", "set    ", "get    ",
	};
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	char cbuf[9] = { 0 };
	if ((b->rheader == 0 && cycles == 0) || (b->rheader && ((cycles % b->rheader) == 0))) {
		if (fprintf(b->trace, ".-------+------+------------+------+------+------+------.\n") < 0)
			return -1;
		if (fprintf(b->trace, "| cycl  |  pc  |  command   |  acc |  op1 |  flg | leds |\n") < 0)
			return -1;
		if (fprintf(b->trace, ".-------+------+------------+------+------+------+------.\n") < 0)
			return -1;
	}
	if (snprintf(cbuf, sizeof cbuf - 1, "%s       ", commands[cmd]) < 0)
		return -1;
	if (b->dec)
		return fprintf(b->trace, "| %5u | %4u | %2u:%s | %4u | %4u | %4u | %4u |\n", 
				cycles, (unsigned)pc, (unsigned)cmd, cbuf, 
				(unsigned)acc, (unsigned)op1, (unsigned)flg, 
				(unsigned)b->leds);
	return fprintf(b->trace, "| %5x | %4x | %2x:%s | %4x | %4x | %4x | %4x |\n", 
			cycles, (unsigned)pc, (unsigned)cmd, cbuf, 
			(unsigned)acc, (unsigned)op1, (unsigned)flg, 
			(unsigned)b->leds);
}

static inline unsigned bits(unsigned b) {
	unsigned r = 0;
	do if (b & 1) r++; while (b >>= 1);
	return r;
}

static inline mw_t rotl(const mw_t value, unsigned shift) {
	shift &= (sizeof(value) * CHAR_BIT) - 1u;
	if (!shift)
		return value;
	return (value << shift) | (value >> ((sizeof(value) * CHAR_BIT) - shift));
}

static inline mw_t rotr(const mw_t value, unsigned shift) {
	shift &= (sizeof(value) * CHAR_BIT) - 1u;
	if (!shift)
		return value;
	return (value >> shift) | (value << ((sizeof(value) * CHAR_BIT) - shift));
}

static inline mw_t shiftl(const int type, const mw_t value, unsigned shift) {
	return type ? rotl(value, shift) : value << shift;
}

static inline mw_t shiftr(const int type, const mw_t value, unsigned shift) {
	return type ? rotr(value, shift) : value >> shift;
}

static inline mw_t add(mw_t a, mw_t b, mw_t *carry) {
	assert(carry);
	const mw_t parry = !!(*carry & 1u);
	const mw_t r = a + b + parry;
	*carry &= ~(1u << fCy);
	if (r < (a + parry) && r < (b + parry))
		*carry |= (1u << fCy);
	return r;
}

static inline mw_t bload(bcpu_t *b, mw_t addr) {
	assert(b);
	if (!(0x8000ul & addr)) {
		if (addr >= MSIZE)
			return 0;
		return b->m[addr % MSIZE];
	}
	switch (addr & 0x7) {
	case 0: return b->switches;
	case 1: return (1u << 11u) | (b->ch & 0xFF);
	}
	return 0;
}

static inline void bstore(bcpu_t *b, mw_t addr, mw_t val) {
	assert(b);
	if (!(0x8000ul & addr)) {
		if (addr >= MSIZE)
			return;
		b->m[addr % MSIZE] = val;
		return;
	}
	switch (addr & 0x7) {
	case 0: b->leds = val; break;
	case 1: 
		if (val & (1u << 13)) {
			fputc(val & 0xFFu, b->out);
			fflush(b->out);
		}
		if (val & (1u << 10))
			b->ch = fgetc(b->in);
		break;
	case 2: /* TX control */ break;
	case 3: /* RX control */ break;
	case 4: /* UART control */ break;
	}
}

static int bcpu(bcpu_t *b, const unsigned cycles) {
	assert(b);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg;
	const unsigned forever = cycles == 0;
       	unsigned count = 0;
	flg |= (1u << fZ);

	for (; count < cycles || forever; count++) {
		if (pc >= MSIZE)
			debug(b, "{INVALID PC: %u}", (unsigned)pc);
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		const int rot    = !!(flg & (1u << fROT));
		trace(b, count, pc, flg, acc, op1, cmd);
		if (flg & (1u << fHLT)) { /* HALT */
			debug(b, "{HALT}");
			goto halt;
		}
		if (flg & (1u << fR)) { /* RESET */
			debug(b, "{RESET}");
			pc = 0;
			acc = 0;
			flg = 0;
		}
		flg &= ~((1u << fZ) | (1u << fNg) | (1u << fPAR));
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */
		flg |= ((bits(acc) & 1u)) << fPAR;  /* set parity bit    */

		const int loadit = !(cmd & 0x8) && (flg & (1u << fIND));
		const mw_t lop = loadit ? bload(b, op1) : op1; 
		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                            break; /* OR      */
		case 0x1: acc &= ((loadit ? 0: 0xF000) | lop);   break; /* AND     */
		case 0x2: acc ^= lop;                            break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);             break; /* ADD     */

		case 0x4: acc = shiftl(rot, acc, bits(lop));     break; /* LSHIFT  */
		case 0x5: acc = shiftr(rot, acc, bits(lop));     break; /* RSHIFT  */
		case 0x6: acc = bload(b, lop);                   break; /* LOAD    */
		case 0x7: bstore(b, lop, acc);                   break; /* STORE   */

		case 0x8: acc = bload(b, op1);                   break; /* LOAD-C  */
		case 0x9: bstore(b, op1, acc);                   break; /* STORE-C  */
		case 0xA: acc = op1;                             break; /* LITERAL */
		case 0xB:                                        break; /* UNUSED  */

		case 0xC: pc = op1;                              break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;                    break; /* JUMPZ   */
		case 0xE:                                               /* SET     */
			if (op1 & 0x0800) { bstore(b, 0x8000u | op1, acc); } 
			else { if (op1 & 1) flg = acc; else pc = acc; } 
			break;
		case 0xF:                                               /* GET */
			if (op1 & 0x0800) { acc = bload(b, 0x8000u | op1); } 
			else { if (op1 & 1) acc = flg; else acc = pc; } 
			break;
		default: r = -1; goto halt;
		}

	}
halt:
	b->pc  = pc;
	b->acc = acc;
	b->flg = flg;
	return r;
}

static int load(bcpu_t *b, FILE *input) {
	assert(b);
	assert(input);
	for (size_t i = 0; i < MSIZE; i++) {
		int pc = 0;
		if (fscanf(input, "%x", &pc) != 1)
			break;
		b->m[i] = pc;
	}
	return 0;
}

static int save(bcpu_t *b, FILE *output) {
	assert(b);
	assert(output);
	for (size_t i = 0; i < MSIZE; i++) /* option to save the rest of bcpu_t? */
		if (fprintf(output, "%04x\n", (unsigned)(b->m[i])) < 0)
			return -1;
	return 0;
}

static FILE *fopen_or_die(const char *file, const char *mode) {
	assert(file);
	assert(mode);
	FILE *r = fopen(file, mode);
	if (!r)
		die("unable to open file \"%s\" (mode = %s)", file, mode);
	return r;
}

int main(int argc, char **argv) {
	int cycles = 0x1000, i = 0;
	static bcpu_t b = { .in = NULL };
	b.in    = stdin;
	b.out   = stdout;
	b.trace = stderr;
	FILE *file = stdin, *hex = NULL;
	for (i = 1; i < argc; i++) {
		if (argv[i][0] != '-')
			break;
		for (int j = 1; argv[i][j]; j++)
			switch (argv[i][j]) {
			case '-': i++; goto done;
			case 'c':
				  if (++i >= argc)
					  die("'c' option requires numeric argument");
				  cycles = atoi(argv[i]);
				  goto fin;
			case 'h': return printf("usage: %s -[tsfed] [-c cycles] input.hex? out.hex?\n", argv[0]), 0;
			case 'e': b.rheader = 32;   break;
			case 's': b.trace = NULL;   break;
			case 't': b.trace = stderr; break;
			case 'd': b.dec   = 1;      break;
			default:
				  die("invalid option -- %c", argv[i][j]);
			}
		fin:
			;
	}
done:

	if (i < argc)
		file = fopen_or_die(argv[i++], "rb");
	if (i < argc)
		hex  = fopen_or_die(argv[i++], "wb");
	if (load(&b, file) < 0)
		die("loading hex file failed");
	if (bcpu(&b, cycles) < 0)
		die("running failed");
	if (hex && save(&b, hex) < 0)
		die("saving file failed");
	return 0; /* dying cleans everything up */
}

