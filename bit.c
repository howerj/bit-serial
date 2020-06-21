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

#define CONFIG_TRACER_ON (1)
#define MSIZE            (4096u)
#define MAX_VARS         (256u)
#define NELEM(X)         (sizeof(X)/sizeof(X[0]))
#define MAX_FILE         (128*1024)
#define MAX_NAME         (32)

typedef uint16_t mw_t; /* machine word */
typedef struct { mw_t pc, acc, flg, m[MSIZE]; } bcpu_t;
typedef struct { FILE *in, *out; mw_t ch, leds, switches; } bcpu_io_t;
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

static inline int trace(bcpu_t *b, bcpu_io_t *io, FILE *tracer, 
		unsigned cycles, const mw_t pc, const mw_t flg, 
		const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	assert(io);
	if (!tracer)
		return 0;
	static const char *commands[] = { 
		"or",     "and",     "xor",     "add",  
		"lshift", "rshift",  "load",    "store",
		"load-c", "store-c", "literal", "unused",
		"jump",   "jumpz",   "set",     "get",
	};
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	char cbuf[9] = { 0 };
	snprintf(cbuf, sizeof cbuf - 1, "%s       ", commands[cmd]);
	return fprintf(tracer, "%4x: %4x %2x:%s %4x %4x %4x %4x\n", 
			cycles, (unsigned)pc, (unsigned)cmd, cbuf, 
			(unsigned)acc, (unsigned)op1, (unsigned)flg, 
			(unsigned)io->leds);
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

static inline mw_t bload(bcpu_t *b, bcpu_io_t *io, int is_io, mw_t addr) {
	assert(b);
	assert(io);
	if (is_io) {
		switch (addr & 0x7) {
		case 0: return io->switches;
		case 1: return (1u << 11u) | (io->ch & 0xFF);
		}
		return 0;
	}
	return b->m[addr % MSIZE];
}

static inline void bstore(bcpu_t *b, bcpu_io_t *io, int is_io, mw_t addr, mw_t val) {
	assert(b);
	assert(io);
	if (is_io) {
		switch (addr & 0x7) {
		case 0: io->leds = val; break;
		case 1: 
			if (val & (1u << 13)) {
				fputc(val & 0xFFu, io->out);
				fflush(io->out);
			}
			if (val & (1u << 10))
				io->ch = fgetc(io->in);
			break;
		case 2: /* TX control */ break;
		case 3: /* RX control */ break;
		case 4: /* UART control */ break;
		}
	} else {
		b->m[addr % MSIZE] = val;
	}
}

static int bcpu(bcpu_t *b, bcpu_io_t *io, FILE *tracer, const unsigned cycles) {
	assert(b);
	assert(io);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg;
	const unsigned forever = cycles == 0;
       	unsigned count = 0;
	for (; count < cycles || forever; count++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		const int rot    = !!(flg & (1u << fROT));
		if (CONFIG_TRACER_ON)
			trace(b, io, tracer, count, pc, flg, acc, op1, cmd);
		if (flg & (1u << fHLT)) /* HALT */
			goto halt;
		if (flg & (1u << fR)) { /* RESET */
			pc = 0;
			acc = 0;
			flg = 0;
		}
		flg &= ~((1u << fZ) | (1u << fNg) | (1u << fPAR));
		flg |= ((!acc) << fZ);              /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << fNg); /* set negative flag */
		flg |= (!(bits(acc) & 1u)) << fPAR; /* set parity bit    */

		const int loadit = !(cmd & 0x4) && (flg & (1u << fIND));
		const mw_t lop = loadit ? bload(b, io, 0, op1) : op1; 
		pc++;
		switch (cmd) {
		case 0x0: acc |= lop;                            break; /* OR      */
		case 0x1: acc &= ((loadit ? 0: 0xF000) | lop);   break; /* AND     */
		case 0x2: acc ^= lop;                            break; /* XOR     */
		case 0x3: acc = add(acc, lop, &flg);             break; /* ADD     */

		case 0x4: acc = shiftl(rot, acc, bits(lop));     break; /* LSHIFT  */
		case 0x5: acc = shiftr(rot, acc, bits(lop));     break; /* RSHIFT  */
		case 0x6: acc = bload(b, io, 0, lop);            break; /* LOAD    */
		case 0x7: bstore(b, io, 0, lop, acc);            break; /* STORE   */

		case 0x8: acc = bload(b, io, 0, op1);            break; /* LOAD-C  */
		case 0x9: bstore(b, io, 0, op1, acc);            break; /* STORE-C  */
		case 0xA: acc = op1;                             break; /* LITERAL */
		case 0xB:                                        break; /* UNUSED  */

		case 0xC: pc = op1;                              break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;                    break; /* JUMPZ   */
		case 0xE:                                               /* SET     */
			if (op1 & 0x0800) { bstore(b, io, 1, 0x8000u | op1, acc); } 
			else { if (op1 & 1) flg = acc; else pc = acc; } 
			break;
		case 0xF:                                               /* GET */
			if (op1 & 0x0800) { acc = bload(b, io, 1, 0x8000u | op1); } 
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
	int cycles = 0x1000;
	static bcpu_t b = { 0, 0, 0, { 0 } };
	bcpu_io_t io = { .in = stdin, .out = stdout };
	FILE *file = stdin, *trace = stderr, *hex = NULL;
	if (argc < 2)
		die("usage: %s -[tsf] input.hex? out.hex?", argv[0]);
	if (argc >= 3)
		file = fopen_or_die(argv[2], "rb");
	if (argc >= 4)
		hex     = fopen_or_die(argv[3], "wb");
	for (size_t i = 0; argv[1][i]; i++)
		switch (argv[1][i]) {
		case '-':                   break;
		case 't': trace   = stderr; break;
		case 's': trace   = NULL;   break;
		case 'f': cycles  = 0;      break;
		default:  die("invalid option -- %c", argv[1][i]);
		}
	if (load(&b, file) < 0)
		die("loading hex file failed");
	if (bcpu(&b, &io, trace, cycles) < 0)
		die("running failed");
	if (hex && save(&b, hex) < 0)
		die("saving file failed");
	return 0; /* dying cleans everything up */
}

